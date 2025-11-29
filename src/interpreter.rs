use crate::parser::Tree;
use crate::util::insert_or_remove;
use crate::{guard, match_ok, source_loc};
use std::collections::HashMap;
use std::fmt::Write;
use std::ops::Deref;

#[derive(Debug, Clone, Default)]
pub struct TypeContext<'a> {
    pub error_log: String,
    pub variables: HashMap<&'a str, Option<TypeInfo>>,
}

#[derive(Debug, Clone, Default)]
pub struct RuntimeContext<'a> {
    pub variables: HashMap<&'a str, Value>,
}

#[derive(Debug, PartialEq, Eq, Clone, Default)]
pub enum TypeInfo {
    #[default]
    Unit,
    Type(Box<TypeInfo>),
    Int64,
    Array(Box<TypeInfo>),
}

#[derive(Debug, Clone, Default)]
pub enum Value {
    #[default]
    Unit,
    Int64(i64),
    Type(TypeInfo),
    Array(Vec<Value>),
}

#[derive(Debug, Clone)]
pub struct TypedTree<'a>(TypeInfo, TypedOp<'a>);

#[derive(Debug, Clone)]
pub enum TypedOp<'a> {
    Const(Value),
    LocalVar(usize, &'a str, Box<TypedTree<'a>>, Box<TypedTree<'a>>),
    LocalGet(usize, &'a str),
    LocalSet(usize, &'a str, Box<TypedTree<'a>>),
    Arithmetic(&'a str, Box<TypedTree<'a>>, Box<TypedTree<'a>>),
    Seq(Box<TypedTree<'a>>, Box<TypedTree<'a>>),
    Array(Vec<TypedOp<'a>>),
    ArrayT(Box<TypedTree<'a>>),
    ArrayGet(Box<TypedOp<'a>>, Box<TypedOp<'a>>),
    ArraySet(Box<TypedOp<'a>>, Box<TypedOp<'a>>, Box<TypedTree<'a>>),
}

impl TypeInfo {
    pub fn zero(&self) -> Value {
        match self {
            Self::Unit => Value::Unit,
            Self::Type(_) => Value::Type(TypeInfo::Unit),
            Self::Int64 => Value::Int64(0),
            Self::Array(_) => Value::Array(Vec::new()),
        }
    }
}

pub fn into_typed_tree<'a>(ctx: &mut TypeContext<'a>, tree: &'a Tree) -> Option<TypedTree<'a>> {
    match tree {
        Tree::Atom(var) => match ctx.variables.get(&var[..]) {
            None => {
                writeln!(&mut ctx.error_log, "Unknown variable {var}").unwrap();
                None
            }
            Some(None) => {
                // Errors about variable types do not make noise as errors about missing variables
                None
            }
            Some(Some(found)) => Some(TypedTree(found.clone(), TypedOp::LocalGet(0, var))),
        },
        Tree::Array(subtree) => {
            guard!(&mut ctx.error_log, !subtree.is_empty());
            let first = match_ok!(&mut ctx.error_log, &subtree[0], Tree::Atom(x) => x)?;
            match &first[..] {
                "+" | "-" | "*" | "/" | "%" => {
                    guard!(&mut ctx.error_log, subtree.len() >= 3);
                    let mut out_opt = into_typed_tree(ctx, &subtree[1]);
                    if let Some(lhs) = &out_opt {
                        // Not a guard in order to collect other errors
                        match_ok!(&mut ctx.error_log, lhs.0, TypeInfo::Int64 => ());
                    }
                    for subtree_it in &subtree[2..] {
                        if let Some(rhs) = into_typed_tree(ctx, subtree_it) {
                            match_ok!(&mut ctx.error_log, rhs.0, TypeInfo::Int64 => ());
                            if let Some(lhs) = out_opt {
                                out_opt = Some(TypedTree(
                                    TypeInfo::Int64,
                                    TypedOp::Arithmetic(first, Box::new(lhs), Box::new(rhs)),
                                ));
                            }
                        }
                    }
                    out_opt
                }
                "let" => {
                    guard!(&mut ctx.error_log, subtree.len() == 4);
                    let var_opt = match_ok!(&mut ctx.error_log, &subtree[1], Tree::Atom(x) => x);
                    let val_opt = into_typed_tree(ctx, &subtree[2]);
                    match var_opt {
                        None => {
                            into_typed_tree(ctx, &subtree[3]);
                            None
                        }
                        Some(var) => {
                            let (var_type_opt, val_opt) = match val_opt {
                                None => (None, None),
                                Some(x) => (Some(x.0), Some(x.1)),
                            };
                            let old_type = ctx.variables.insert(&var[..], var_type_opt);
                            let body_opt = into_typed_tree(ctx, &subtree[3]);
                            let var_type_opt = insert_or_remove(&mut ctx.variables, var, old_type);
                            let var_type = var_type_opt??;
                            let val = val_opt?;
                            let body = body_opt?;
                            Some(TypedTree(
                                body.0.clone(),
                                TypedOp::LocalVar(
                                    0,
                                    var,
                                    Box::new(TypedTree(var_type, val)),
                                    Box::new(body),
                                ),
                            ))
                        }
                    }
                }
                "var" => {
                    guard!(&mut ctx.error_log, subtree.len() == 4);
                    let var_opt = match_ok!(&mut ctx.error_log, &subtree[1], Tree::Atom(x) => x);
                    let val_opt = into_typed_tree(ctx, &subtree[2]);
                    let var_type_opt = match_ok!(&mut ctx.error_log, val_opt, Some(TypedTree(TypeInfo::Type(t), _)) => *t);
                    match var_opt {
                        None => {
                            into_typed_tree(ctx, &subtree[3]);
                            None
                        }
                        Some(var) => {
                            let old_type = ctx.variables.insert(&var[..], var_type_opt);
                            let body_opt = into_typed_tree(ctx, &subtree[3]);
                            let var_type_opt = insert_or_remove(&mut ctx.variables, var, old_type);
                            let var_type = var_type_opt??;
                            let body = body_opt?;
                            let zero = var_type.zero();
                            Some(TypedTree(
                                body.0.clone(),
                                TypedOp::LocalVar(
                                    0,
                                    var,
                                    Box::new(TypedTree(var_type, TypedOp::Const(zero))),
                                    Box::new(body),
                                ),
                            ))
                        }
                    }
                }
                "seq" => {
                    guard!(&mut ctx.error_log, subtree.len() >= 2);
                    let mut out_opt = into_typed_tree(ctx, &subtree[1]);
                    for subtree_it in &subtree[2..] {
                        if let Some(rhs) = into_typed_tree(ctx, subtree_it) {
                            if let Some(lhs) = out_opt {
                                out_opt = Some(TypedTree(
                                    TypeInfo::Int64,
                                    TypedOp::Seq(Box::new(lhs), Box::new(rhs)),
                                ));
                            }
                        }
                    }
                    out_opt
                }
                "set" => {
                    guard!(&mut ctx.error_log, subtree.len() == 3);
                    let var_opt = match_ok!(&mut ctx.error_log, &subtree[1], Tree::Atom(x) => x);
                    let val_type_opt = into_typed_tree(ctx, &subtree[2]);
                    let var = &var_opt?[..];
                    let val = val_type_opt?;
                    let var_type =
                        match_ok!(&mut ctx.error_log, ctx.variables.get(var), Some(x) => x)?
                            .as_ref()?;
                    guard!(&mut ctx.error_log, var_type.eq(&val.0));
                    Some(TypedTree(
                        TypeInfo::Unit,
                        TypedOp::LocalSet(0, var, Box::new(val)),
                    ))
                }
                "array" => {
                    if subtree.len() == 1 {
                        return Some(TypedTree(
                            TypeInfo::Array(Box::new(TypeInfo::Unit)),
                            TypedOp::Array(Vec::new()),
                        ));
                    }
                    let first_opt = into_typed_tree(ctx, &subtree[1]);
                    let mut out_opt = first_opt.map(|x| (x.0, vec![x.1]));
                    for subtree_it in &subtree[2..] {
                        let it_opt = into_typed_tree(ctx, subtree_it);
                        match (&mut out_opt, it_opt) {
                            (Some((first_type, out)), Some(it)) => {
                                if it.0.eq(first_type) {
                                    out.push(it.1);
                                } else {
                                    writeln!(
                                        &mut ctx.error_log,
                                        "Array elements type mismatch: {:?} vs {first_type:?}",
                                        it.0
                                    )
                                    .unwrap();
                                    out_opt = None;
                                }
                            }
                            _ => out_opt = None,
                        }
                    }
                    let (out_type, out_items) = out_opt?;
                    let array_t = TypeInfo::Array(Box::new(out_type.clone()));
                    Some(TypedTree(array_t, TypedOp::Array(out_items)))
                }
                "array-t" => {
                    guard!(&mut ctx.error_log, subtree.len() == 2);
                    let inner1 = into_typed_tree(ctx, &subtree[1])?;
                    let inner2 = match_ok!(&mut ctx.error_log, &inner1.0, TypeInfo::Type(t) => t)?;
                    let array_tt = TypeInfo::Type(Box::new(TypeInfo::Array(inner2.clone())));
                    Some(TypedTree(array_tt, TypedOp::ArrayT(Box::new(inner1))))
                }
                "array-get" => {
                    guard!(&mut ctx.error_log, subtree.len() == 3);
                    let index_opt = into_typed_tree(ctx, &subtree[1]);
                    let array_opt = into_typed_tree(ctx, &subtree[2]);
                    let index = index_opt?;
                    let array = array_opt?;
                    guard!(&mut ctx.error_log, matches!(index.0, TypeInfo::Int64));
                    let inner = match_ok!(&mut ctx.error_log, array.0, TypeInfo::Array(t) => t)?;
                    Some(TypedTree(
                        *inner,
                        TypedOp::ArrayGet(Box::new(index.1), Box::new(array.1)),
                    ))
                }
                "array-set" => {
                    guard!(&mut ctx.error_log, subtree.len() == 4);
                    let index_opt = into_typed_tree(ctx, &subtree[1]);
                    let array_opt = into_typed_tree(ctx, &subtree[2]);
                    let val_opt = into_typed_tree(ctx, &subtree[3]);
                    let index = index_opt?;
                    let array = array_opt?;
                    let val = val_opt?;
                    guard!(&mut ctx.error_log, matches!(index.0, TypeInfo::Int64));
                    let inner = match_ok!(&mut ctx.error_log, array.0, TypeInfo::Array(t) => t)?;
                    guard!(&mut ctx.error_log, val.0.eq(&inner));
                    Some(TypedTree(
                        *inner,
                        TypedOp::ArraySet(Box::new(index.1), Box::new(array.1), Box::new(val)),
                    ))
                }
                x => {
                    writeln!(&mut ctx.error_log, "Unknown function {x}").unwrap();
                    None
                }
            }
        }
        Tree::Int64(x) => Some(TypedTree(TypeInfo::Int64, TypedOp::Const(Value::Int64(*x)))),
    }
}

pub fn interpret<'a>(ctx: &mut RuntimeContext<'a>, tree: &'a Tree) -> Result<Value, String> {
    match tree {
        Tree::Atom(var) => ctx
            .variables
            .get(&var[..])
            .cloned()
            .ok_or_else(|| format!("Unknown variable {var:?}")),
        Tree::Array(arr) => {
            guard!(!arr.is_empty());
            match &arr[0] {
                Tree::Atom(s) => match &s[..] {
                    "+" => {
                        let mut acc = match_ok!(interpret(ctx, &arr[1])?, Value::Int64(x) => x)?;
                        for x in &arr[2..] {
                            let y = match_ok!(interpret(ctx, x)?, Value::Int64(y) => y)?;
                            acc = acc.wrapping_add(y);
                        }
                        Ok(Value::Int64(acc))
                    }
                    "-" => {
                        let mut acc = match_ok!(interpret(ctx, &arr[1])?, Value::Int64(x) => x)?;
                        for x in &arr[2..] {
                            let y = match_ok!(interpret(ctx, x)?, Value::Int64(y) => y)?;
                            acc = acc.wrapping_sub(y);
                        }
                        Ok(Value::Int64(acc))
                    }
                    "*" => {
                        let mut acc = match_ok!(interpret(ctx, &arr[1])?, Value::Int64(y) => y)?;
                        for x in &arr[2..] {
                            let y = match_ok!(interpret(ctx, x)?, Value::Int64(y) => y)?;
                            acc = acc.wrapping_mul(y);
                        }
                        Ok(Value::Int64(acc))
                    }
                    "/" => {
                        let mut acc = match_ok!(interpret(ctx, &arr[1])?, Value::Int64(y) => y)?;
                        for x in &arr[2..] {
                            let y = match_ok!(interpret(ctx, x)?, Value::Int64(y) => y)?;
                            guard!(y != 0);
                            acc /= y;
                        }
                        Ok(Value::Int64(acc))
                    }
                    "let" => {
                        guard!(arr.len() == 4);
                        let var = match_ok!(&arr[1], Tree::Atom(x) => x)?;
                        let val = interpret(ctx, &arr[2])?;
                        let old_val = ctx.variables.insert(var, val);
                        let body = interpret(ctx, &arr[3]);
                        insert_or_remove(&mut ctx.variables, var, old_val);
                        body
                    }
                    "var" => {
                        guard!(arr.len() == 4);
                        let var = match_ok!(&arr[1], Tree::Atom(x) => x)?;
                        let typ_val = interpret(ctx, &arr[2])?;
                        let typ = match_ok!(&typ_val, Value::Type(x) => x)?;
                        let old_val = ctx.variables.insert(var, typ.zero());
                        let body = interpret(ctx, &arr[3]);
                        insert_or_remove(&mut ctx.variables, var, old_val);
                        body
                    }
                    "seq" => {
                        let mut out = Value::Unit;
                        for x in &arr[1..] {
                            out = interpret(ctx, x)?;
                        }
                        Ok(out)
                    }
                    "set" => {
                        guard!(arr.len() == 3);
                        let var = match_ok!(&arr[1], Tree::Atom(x) => x)?;
                        let val = interpret(ctx, &arr[2])?;
                        let pos = ctx
                            .variables
                            .get_mut(&var[..])
                            .ok_or_else(|| format!("Undeclared variable {var:?}"))?;
                        *pos = val;
                        Ok(Value::Unit)
                    }
                    "array" => {
                        let mut out = Vec::new();
                        for x in &arr[1..] {
                            out.push(interpret(ctx, x)?);
                        }
                        Ok(Value::Array(out))
                    }
                    "array-t" => {
                        guard!(arr.len() == 2);
                        let inner = match_ok!(interpret(ctx, &arr[1])?, Value::Type(x) => x)?;
                        Ok(Value::Type(TypeInfo::Array(Box::new(inner))))
                    }
                    "array-get" => {
                        guard!(arr.len() == 3);
                        let index = match_ok!(interpret(ctx, &arr[1])?, Value::Int64(x) => x)?;
                        let mut array = match_ok!(interpret(ctx, &arr[2])?, Value::Array(x) => x)?;
                        guard!(0 <= index && (index as usize) < array.len());
                        Ok(array.swap_remove(index as usize))
                    }
                    "array-set" => {
                        guard!(arr.len() == 4);
                        let val = interpret(ctx, &arr[3])?;
                        let index = match_ok!(interpret(ctx, &arr[1])?, Value::Int64(x) => x)?;
                        let var = match_ok!(&arr[2], Tree::Atom(x) => x)?;
                        let array_mut_val = ctx
                            .variables
                            .get_mut(&var[..])
                            .ok_or_else(|| format!("Array {var:?} not found"))?;
                        let array_mut = match_ok!(array_mut_val, Value::Array(x) => x)?;
                        guard!(0 <= index && (index as usize) < array_mut.len());
                        array_mut[index as usize] = val;
                        Ok(Value::Unit)
                    }
                    _ => Err(format!("Unknown function {s}")),
                },
                Tree::Array(_) => Err("Array used as function".into()),
                Tree::Int64(_) => Err("Number used as function".into()),
            }
        }
        &Tree::Int64(x) => Ok(Value::Int64(x)),
    }
}

pub fn interpret_no_context(tree: &Tree) -> Result<Value, String> {
    let mut ctx = RuntimeContext::default();
    ctx.variables.insert("i64", Value::Type(TypeInfo::Int64));
    interpret(&mut ctx, tree)
}

pub fn parse_interpret(s: &str) -> Result<Value, String> {
    let mut ctx = RuntimeContext::default();
    ctx.variables.insert("i64", Value::Type(TypeInfo::Int64));
    interpret(&mut ctx, &s.parse()?)
}

impl<'a> TryFrom<&'a Tree> for TypedTree<'a> {
    type Error = String;
    fn try_from(value: &'a Tree) -> Result<Self, Self::Error> {
        let mut ctx = TypeContext::default();
        ctx.variables
            .insert("i64", Some(TypeInfo::Type(Box::new(TypeInfo::Int64))));
        into_typed_tree(&mut ctx, value).ok_or(ctx.error_log)
    }
}
