use std::{borrow::Borrow, collections::HashMap, hash::Hash};

#[macro_export]
macro_rules! source_loc {
    () => {
        concat!(file!(), ":", line!(), ":", column!())
    };
}

#[macro_export]
macro_rules! guard_opt {
    ($e:expr) => {
        (if $e { Some(()) } else { None })?
    };
}

#[macro_export]
macro_rules! guard {
    ($e:expr) => {
        (if $e {
            Ok(())
        } else {
            Err(concat!(
                "Guard fail ",
                stringify!($e),
                " at ",
                $crate::source_loc!(),
                "\n",
            ))
        })?
    };

    ($logger:expr, $e:expr) => {
        (if $e {
            Some(())
        } else {
            $logger.push_str(concat!(
                "Guard fail ",
                stringify!($e),
                " at ",
                $crate::source_loc!(),
                "\n",
            ));
            None
        })?
    };
}

#[macro_export]
macro_rules! match_ok {
    ($e:expr, $p:pat $(if $g:expr)? => $r:expr) => {
        match $e {
            $p $(if $g)? => Ok($r),
            _ => Err(concat!(
                "Match fail: ",
                stringify!($e),
                " as ",
                stringify!($p),
                " at ",
                $crate::source_loc!(),
                "\n",
            )),
        }
    };

    ($logger:expr, $e:expr, $p:pat $(if $g:expr)? => $r:expr) => {
        match $e {
            $p $(if $g)? => Some($r),
            _ => {
                $logger.push_str(concat!(
                    "Match fail: ",
                    stringify!($e),
                    " as ",
                    stringify!($p),
                    " at ",
                    $crate::source_loc!(),
                    "\n",
                ));
                None
            }
        }
    };
}

pub fn insert_or_remove<K: Eq + Hash + Copy, V>(
    map: &mut HashMap<K, V>,
    key: K,
    item: Option<V>,
) -> Option<V> {
    match item {
        None => map.remove(&key),
        Some(val) => map.insert(key, val),
    }
}

pub fn ok_or_log<T, E: Borrow<str>>(error_log: &mut String, res: Result<T, E>) -> Option<T> {
    match res {
        Ok(x) => Some(x),
        Err(err) => {
            error_log.push_str(err.borrow());
            error_log.push('\n');
            None
        }
    }
}
