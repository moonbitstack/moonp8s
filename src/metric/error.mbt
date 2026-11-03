// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The one error this library raises: a request it will not honour, with the
/// reason in the message. Messages carry the offending value and, where a
/// position is meaningful, an `at` offset counted from zero.
pub(all) suberror Refused {
  Refused(String)
}

///|
/// The reason a request was refused.
pub fn Refused::message(self : Refused) -> String {
  match self {
    Refused(msg) => msg
  }
}
