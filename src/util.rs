use std::{collections::HashMap, hash::Hash};

#[macro_export]
macro_rules! declare_enum_as {
    ($enum_name:ty, $fn_name:ident $variant_name:ident($($inner:ident),+) -> $out_type:ty) => {
        impl $enum_name {
            pub fn $fn_name(self) -> ::core::result::Result<$out_type, &'static str> {
                match self {
                    Self::$variant_name($($inner),+) => ::core::result::Result::Ok(($($inner),+)),
                    _ => ::core::result::Result::Err(concat!(stringify!($variant_name), " expected")),
                }
            }
        }
    };

    ($enum_name:ty, $fn_name:ident &$variant_name:ident($($inner:ident),+) -> $out_type:ty) => {
        impl $enum_name {
            pub fn $fn_name(&self) -> ::core::result::Result<&$out_type, &'static str> {
                match self {
                    Self::$variant_name($($inner),+) => ::core::result::Result::Ok(($($inner),+)),
                    _ => ::core::result::Result::Err(concat!(stringify!($variant_name), " expected")),
                }
            }
        }
    };

    ($enum_name:ty, $fn_name:ident &mut $variant_name:ident($($inner:ident),+) -> $out_type:ty) => {
        impl $enum_name {
            pub fn $fn_name(&mut self) -> ::core::result::Result<&mut $out_type, &'static str> {
                match self {
                    Self::$variant_name($($inner),+) => ::core::result::Result::Ok(($($inner),+)),
                    _ => ::core::result::Result::Err(concat!(stringify!($variant_name), " expected")),
                }
            }
        }
    };

    ($enum_name:ty, $fn_name:ident copy $variant_name:ident($($inner:ident),+) -> $out_type:ty) => {
        impl $enum_name {
            pub fn $fn_name(&self) -> ::core::result::Result<$out_type, &'static str> {
                match self {
                    Self::$variant_name($($inner),+) => ::core::result::Result::Ok(($(*$inner),+)),
                    _ => ::core::result::Result::Err(concat!(stringify!($variant_name), " expected")),
                }
            }
        }
    };
}

pub fn replace_or_remove<K: Eq + Hash + Copy, V>(map: &mut HashMap<K, V>, key: K, item: Option<V>) {
    match item {
        None => map.remove(&key),
        Some(val) => map.insert(key, val),
    };
}
