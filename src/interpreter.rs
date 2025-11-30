use crate::parser::Tree;
use crate::phase2::{ArithmeticOp, Tree2};
use crate::util::insert_or_remove;
use crate::{guard, match_ok};
use std::collections::HashMap;
use std::fmt::Write;

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
    Arithmetic(ArithmeticOp, Vec<TypedTree<'a>>),
    Seq(Vec<TypedTree<'a>>),
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

pub fn into_typed_tree<'a>(ctx: &mut TypeContext<'a>, tree: &'a Tree2) -> Option<TypedTree<'a>> {
    match tree {
        Tree2::Ident(var) => match ctx.variables.get(&var[..]) {
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
        Tree2::LetVal(var, val, body) => {
            let (var_type_opt, val_opt) = match into_typed_tree(ctx, &val) {
                None => (None, None),
                Some(x) => (Some(x.0), Some(x.1)),
            };
            let old_type = ctx.variables.insert(var, var_type_opt);
            let body_opt = into_typed_tree(ctx, body);
            let var_type_opt = insert_or_remove(&mut ctx.variables, var, old_type);
            let body = body_opt?;
            Some(TypedTree(
                body.0.clone(),
                TypedOp::LocalVar(
                    0,
                    var,
                    Box::new(TypedTree(var_type_opt??, val_opt?)),
                    Box::new(body),
                ),
            ))
        }
        Tree2::LetType(var, val, body) => {
            let val_opt = into_typed_tree(ctx, &val);
            let var_type_opt =
                match_ok!(&mut ctx.error_log, val_opt, Some(TypedTree(TypeInfo::Type(t), _)) => *t);
            let old_type = ctx.variables.insert(var, var_type_opt);
            let body_opt = into_typed_tree(ctx, &body);
            let var_type_opt = insert_or_remove(&mut ctx.variables, var, old_type);
            let var_type = var_type_opt??;
            let zero = var_type.zero();
            let body = body_opt?;
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
        Tree2::Seq(items) => {
            let mut out_opt = Some(Vec::new());
            for it in items {
                let item = into_typed_tree(ctx, it);
                match (&mut out_opt, item) {
                    (Some(out), Some(item)) => out.push(item),
                    _ => out_opt = None,
                }
            }
            let out = out_opt?;
            Some(TypedTree(out.last()?.0.clone(), TypedOp::Seq(out)))
        }
        Tree2::Set(var, val) => {
            let val = into_typed_tree(ctx, val)?;
            let var_type =
                match_ok!(&mut ctx.error_log, ctx.variables.get(&var[..]), Some(x) => x)?
                    .as_ref()?;
            guard!(&mut ctx.error_log, var_type.eq(&val.0));
            Some(TypedTree(
                TypeInfo::Unit,
                TypedOp::LocalSet(0, var, Box::new(val)),
            ))
        }
        Tree2::LiteralInt64(x) => {
            Some(TypedTree(TypeInfo::Int64, TypedOp::Const(Value::Int64(*x))))
        }
        Tree2::LiteralArray(items) => {
            if items.is_empty() {
                return Some(TypedTree(
                    TypeInfo::Array(Box::new(TypeInfo::Unit)),
                    TypedOp::Array(Vec::new()),
                ));
            }
            let first_opt = into_typed_tree(ctx, &items[0]);
            let mut out_opt = first_opt.map(|x| (x.0, vec![x.1]));
            for it in &items[1..] {
                let it_opt = into_typed_tree(ctx, it);
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
            let array_t = TypeInfo::Array(Box::new(out_type));
            Some(TypedTree(array_t, TypedOp::Array(out_items)))
        }
        Tree2::LiteralArrayType(inner) => {
            let inner1 = into_typed_tree(ctx, inner)?;
            let inner2 = match_ok!(&mut ctx.error_log, &inner1.0, TypeInfo::Type(t) => t)?;
            let array_tt = TypeInfo::Type(Box::new(TypeInfo::Array(inner2.clone())));
            Some(TypedTree(array_tt, TypedOp::ArrayT(Box::new(inner1))))
        }
        Tree2::Arithmetic(op, operands) => {
            guard!(&mut ctx.error_log, !operands.is_empty());
            let mut out_opt = Some(Vec::new());
            for operand in operands {
                let rhs_opt = into_typed_tree(ctx, operand);
                let rhs_val_opt = match_ok!(&mut ctx.error_log, rhs_opt, Some(TypedTree(TypeInfo::Int64, x)) => x);
                match (&mut out_opt, rhs_val_opt) {
                    (Some(out), Some(item)) => out.push(TypedTree(TypeInfo::Int64, item)),
                    _ => out_opt = None,
                }
            }
            Some(TypedTree(
                TypeInfo::Int64,
                TypedOp::Arithmetic(*op, out_opt?),
            ))
        }
        Tree2::ArrayGet(array, index) => {
            let array_opt = into_typed_tree(ctx, &array);
            let index = into_typed_tree(ctx, &index)?;
            let array = array_opt?;
            let inner_opt = match_ok!(&mut ctx.error_log, array.0, TypeInfo::Array(t) => t);
            guard!(&mut ctx.error_log, matches!(index.0, TypeInfo::Int64));
            Some(TypedTree(
                *inner_opt?,
                TypedOp::ArrayGet(Box::new(array.1), Box::new(index.1)),
            ))
        }
        Tree2::ArraySet(array, index, val) => {
            let array_opt = into_typed_tree(ctx, &array);
            let index_opt = into_typed_tree(ctx, &index);
            let val = into_typed_tree(ctx, &val)?;
            let array = array_opt?;
            let index = index_opt?;
            let inner = match_ok!(&mut ctx.error_log, array.0, TypeInfo::Array(t) => t)?;
            guard!(&mut ctx.error_log, matches!(index.0, TypeInfo::Int64));
            guard!(&mut ctx.error_log, val.0.eq(&inner));
            Some(TypedTree(
                *inner,
                TypedOp::ArraySet(Box::new(array.1), Box::new(index.1), Box::new(val)),
            ))
        }
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

impl<'a> TryFrom<&'a Tree2> for TypedTree<'a> {
    type Error = String;
    fn try_from(value: &'a Tree2) -> Result<Self, Self::Error> {
        let mut ctx = TypeContext::default();
        ctx.variables
            .insert("i64", Some(TypeInfo::Type(Box::new(TypeInfo::Int64))));
        into_typed_tree(&mut ctx, value).ok_or(ctx.error_log)
    }
}

pub fn parse_interpret(s: &str) -> Result<String, String> {
    let tree1: Tree = s.parse()?;
    let tree2 = Tree2::try_from(&tree1)?;
    let tree3 = TypedTree::try_from(&tree2)?;
    Ok(format!("{tree3:?}"))
}
