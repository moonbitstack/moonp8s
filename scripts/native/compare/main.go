// Native histogram vectors from client_golang: each scenario's settings, its observations as
// float64 bits, and the Histogram message client_golang writes for them. gen_vectors.py turns
// the output into a test that replays the observations through moonp8s and compares bytes.
//
//	go run . > vectors.json
//	go run . -serve :8080      serve the sizes 10-native observes, for check_scrape.py
//
// The created timestamp is removed, since it is the time of the run. No scenario uses a minimum
// reset duration or exemplars, which depend on the clock as well; those are tested with an
// injected clock in the library's own tests.
package main

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math"
	"math/rand"
	"net/http"
	"os"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	dto "github.com/prometheus/client_model/go"
	"google.golang.org/protobuf/proto"
)

type scenario struct {
	Name             string    `json:"name"`
	Factor           float64   `json:"factor"`
	ZeroThreshold    float64   `json:"zero_threshold"`
	MaxBuckets       uint32    `json:"max_buckets"`
	MaxZeroThreshold float64   `json:"max_zero_threshold"`
	Buckets          []float64 `json:"buckets"`
	Values           []string  `json:"values"`
	Message          string    `json:"message"`
	values           []float64
}

func bits(values []float64) []string {
	out := make([]string, len(values))
	for i, v := range values {
		out[i] = fmt.Sprintf("%016x", math.Float64bits(v))
	}
	return out
}

// mixed is a spread of magnitudes and signs, with zero, the extremes, and values on and beside
// powers of two, which are bucket boundaries at every schema. It holds one infinity, positive
// for an odd seed and negative for an even one: both together make the sum a NaN, whose sign
// bit is the processor's choice (set on x86, clear on arm64), not the library's.
func mixed(seed int64, n int) []float64 {
	r := rand.New(rand.NewSource(seed))
	var out []float64
	for i := 0; i < n; i++ {
		v := math.Exp(r.Float64()*40 - 20)
		if r.Intn(3) == 0 {
			v = -v
		}
		out = append(out, v)
	}
	for k := -12; k <= 12; k++ {
		p := math.Ldexp(1, k)
		out = append(out, p, math.Nextafter(p, 0), math.Nextafter(p, math.Inf(1)), -p)
	}
	inf := math.Inf(1)
	if seed%2 == 0 {
		inf = math.Inf(-1)
	}
	out = append(out, 0, 0, 1e-300, 5e-324, -5e-324, 1e300, -1e300, math.MaxFloat64,
		-math.MaxFloat64, inf, 2.938735877055719e-39)
	return out
}

func run(s *scenario) {
	threshold := s.ZeroThreshold
	if threshold == 0 {
		threshold = prometheus.NativeHistogramZeroThresholdZero
	}
	h := prometheus.NewHistogram(prometheus.HistogramOpts{
		Name:                            "vector",
		Help:                            "vector",
		Buckets:                         s.Buckets,
		NativeHistogramBucketFactor:     s.Factor,
		NativeHistogramZeroThreshold:    threshold,
		NativeHistogramMaxBucketNumber:  s.MaxBuckets,
		NativeHistogramMaxZeroThreshold: s.MaxZeroThreshold,
		NativeHistogramMaxExemplars:     -1,
	})
	for _, v := range s.values {
		h.Observe(v)
	}
	var m dto.Metric
	if err := h.Write(&m); err != nil {
		panic(err)
	}
	m.Histogram.CreatedTimestamp = nil
	body, err := proto.MarshalOptions{Deterministic: true}.Marshal(m.Histogram)
	if err != nil {
		panic(err)
	}
	s.Values = bits(s.values)
	s.Message = hex.EncodeToString(body)
}

// serve exposes the histograms src/examples/10-native builds, fed the same sizes, with the
// settings moonp8s's `native` preset names: factor 1.1, at most 100 buckets, a reset after
// fifteen minutes, the default zero threshold and exemplars.
func serve(addr string) {
	registry := prometheus.NewRegistry()
	sizes := prometheus.NewHistogram(prometheus.HistogramOpts{
		Name:                            "request_size_bytes",
		Help:                            "Request sizes, in native buckets.",
		NativeHistogramBucketFactor:     1.1,
		NativeHistogramMaxBucketNumber:  100,
		NativeHistogramMinResetDuration: 15 * time.Minute,
	})
	classic := prometheus.NewHistogram(prometheus.HistogramOpts{
		Name:    "request_size_classic_bytes",
		Help:    "Request sizes, in classic buckets.",
		Buckets: []float64{100, 1000, 10000},
	})
	registry.MustRegister(sizes, classic)
	for i := 0; i < 500; i++ {
		size := float64((i*i%9973+1)*37) / 7.0
		sizes.Observe(size)
		classic.Observe(size)
	}
	http.Handle("/metrics", promhttp.HandlerFor(registry, promhttp.HandlerOpts{}))
	panic(http.ListenAndServe(addr, nil))
}

func main() {
	if len(os.Args) == 3 && os.Args[1] == "-serve" {
		serve(os.Args[2])
	}
	const zero = 2.938735877055719e-39
	var out []*scenario
	factors := []float64{1.0001, 1.001, 1.003, 1.006, 1.01, 1.02, 1.05, 1.1, 1.2, 1.5, 2, 4, 16, 256, 65536, 1e10, 1e100}
	for i, f := range factors {
		out = append(out, &scenario{Name: fmt.Sprintf("factor %g", f), Factor: f, ZeroThreshold: zero, values: mixed(int64(i+1), 200)})
	}
	out = append(out,
		&scenario{Name: "classic and native", Factor: 1.1, ZeroThreshold: zero, Buckets: prometheus.DefBuckets, values: mixed(101, 300)},
		&scenario{Name: "exact zero bucket, nothing observed", Factor: 1.1},
		&scenario{Name: "exact zero bucket", Factor: 1.1, values: mixed(102, 100)},
		&scenario{Name: "wide zero bucket", Factor: 1.1, ZeroThreshold: 0.001, values: mixed(103, 200)},
		&scenario{Name: "default threshold, nothing observed", Factor: 1.1, ZeroThreshold: zero},
		&scenario{Name: "limit widens the zero bucket", Factor: 1.1, ZeroThreshold: zero, MaxBuckets: 20, MaxZeroThreshold: 0.5, values: mixed(104, 150)},
		&scenario{Name: "limit halves the resolution", Factor: 1.01, ZeroThreshold: zero, MaxBuckets: 10, values: mixed(105, 400)},
		&scenario{Name: "limit down to the coarsest schema", Factor: 1.0001, ZeroThreshold: zero, MaxBuckets: 3, values: mixed(106, 500)},
	)
	for _, s := range out {
		run(s)
	}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", " ")
	if err := enc.Encode(out); err != nil {
		panic(err)
	}
}
