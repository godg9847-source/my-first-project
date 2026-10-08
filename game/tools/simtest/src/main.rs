//! Headless test runner for the battle simulation.
//!
//! Usage: simtest <src-root> <test-script.luau> [args...]
//!
//! It builds a fake Roblox instance tree from the folder <src-root> so that
//! `require(script.Parent.Foo)` works like in Studio, then runs the test script.
//! Only pure-Luau modules (no Roblox APIs) can be required this way.
use mlua::{Lua, Table};
use std::{env, fs, process};

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("usage: simtest <src-root> <test-script.luau> [args...]");
        process::exit(2);
    }
    let lua = Lua::new();
    if let Err(e) = run(&lua, &args) {
        eprintln!("{e}");
        process::exit(1);
    }
}

fn run(lua: &Lua, args: &[String]) -> mlua::Result<()> {
    let g = lua.globals();
    g.set("warn", lua.create_function(|_, msg: mlua::MultiValue| {
        let parts: Vec<String> = msg.iter().map(|v| v.to_string().unwrap_or_default()).collect();
        eprintln!("WARN: {}", parts.join(" "));
        Ok(())
    })?)?;
    g.set("__readfile", lua.create_function(|_, p: String| {
        fs::read_to_string(&p).map_err(mlua::Error::external)
    })?)?;
    g.set("__listdir", lua.create_function(|lua, p: String| {
        let t = lua.create_table()?;
        let mut entries: Vec<(String, bool)> = Vec::new();
        for e in fs::read_dir(&p).map_err(mlua::Error::external)? {
            let e = e.map_err(mlua::Error::external)?;
            let is_dir = e.file_type().map_err(mlua::Error::external)?.is_dir();
            entries.push((e.file_name().to_string_lossy().to_string(), is_dir));
        }
        entries.sort();
        for (i, (name, is_dir)) in entries.into_iter().enumerate() {
            let row = lua.create_table()?;
            row.set("name", name)?;
            row.set("dir", is_dir)?;
            t.set(i + 1, row)?;
        }
        Ok(t)
    })?)?;
    g.set("__load", lua.create_function(|lua, (path, env): (String, Table)| {
        let src = fs::read_to_string(&path).map_err(mlua::Error::external)?;
        lua.load(&src).set_name(format!("@{path}")).set_environment(env).into_function()
    })?)?;
    let argv = lua.create_table()?;
    for (i, a) in args.iter().skip(3).enumerate() {
        argv.set(i + 1, a.as_str())?;
    }
    g.set("ARGS", argv)?;
    g.set("SRC_ROOT", args[1].as_str())?;
    lua.load(include_str!("prelude.luau")).set_name("@prelude").exec()?;
    let src = fs::read_to_string(&args[2]).map_err(mlua::Error::external)?;
    let env = lua.create_table()?;
    let mt = lua.create_table()?;
    mt.set("__index", g.clone())?;
    env.set_metatable(Some(mt));
    lua.load(&src).set_name(format!("@{}", args[2])).set_environment(env).exec()
}
