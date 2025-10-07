// TODO: Remove me when mullvad-api no longer allows undocumented_unsafe_blocks.
#![warn(clippy::undocumented_unsafe_blocks)]
use crate::rest;
use std::ffi::{CStr, CString, NulError};

#[derive(Debug, PartialEq)]
#[repr(C)]
pub enum MullvadApiErrorKind {
    NoError = 0,
    StringParsing = -1,
    SocketAddressParsing = -2,
    AsyncRuntimeInitialization = -3,
    BadResponse = -4,
}

/// MullvadApiErrorKind contains a description and an error kind. If the error kind is
/// `MullvadApiErrorKind` is NoError, the pointer will be nil.
#[derive(Debug)]
#[repr(C)]
pub struct MullvadApiError {
    description: *mut libc::c_char,
    kind: MullvadApiErrorKind,
}

impl MullvadApiError {
    pub fn new(kind: MullvadApiErrorKind, error: &dyn std::error::Error) -> Result<Self, NulError> {
        let description = CString::new(format!("{error:?}: {error}"))?;
        let error = Self::with_str(kind, &description);
        Ok(error)
    }

    pub fn api_err(error: rest::Error) -> Self {
        Self::new(MullvadApiErrorKind::BadResponse, &error)
            .expect("rest::Error messages should not contain an interior nul-byte.")
    }

    pub fn with_str(kind: MullvadApiErrorKind, description: &CStr) -> Self {
        let description = CString::from(description);
        Self {
            description: description.into_raw(),
            kind,
        }
    }

    pub fn ok() -> MullvadApiError {
        Self {
            description: std::ptr::null_mut(),
            kind: MullvadApiErrorKind::NoError,
        }
    }

    pub fn unwrap(&self) {
        if !matches!(self.kind, MullvadApiErrorKind::NoError) {
            // SAFETY: `self.description` was initialized using `CString::into_raw`.
            let desc = unsafe { std::ffi::CStr::from_ptr(self.description) };
            panic!("API ERROR - {:?} - {}", self.kind, desc.to_str().unwrap());
        }
    }

    pub fn drop(self) {
        if !self.description.is_null() {
            // SAFETY: `self.description` was initialized using `CString::into_raw`.
            let _ = unsafe { CString::from_raw(self.description) };
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn mullvad_api_error_drop(error: MullvadApiError) {
    error.drop()
}
