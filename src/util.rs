use std::{collections::HashMap, hash::Hash};

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
                file!(),
                ":",
                line!(),
                ":",
                column!()
            ))
        })?
    };
}

#[macro_export]
macro_rules! match_ok {
    ($e:expr, $p:pat => $r:expr) => {
        match $e {
            $p => Ok($r),
            _ => Err(concat!(
                "Match fail: ",
                stringify!($e),
                " as ",
                stringify!($p),
                " at ",
                file!(),
                ":",
                line!(),
                ":",
                column!()
            )),
        }
    };
}

pub fn replace_or_remove<K: Eq + Hash + Copy, V>(map: &mut HashMap<K, V>, key: K, item: Option<V>) {
    match item {
        None => map.remove(&key),
        Some(val) => map.insert(key, val),
    };
}
