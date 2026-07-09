if package.preload["config"] == nil then
    package.path = "src/?.lua;" .. package.path
end

help = require("help")
get_help_string = help.get_help_string

config = require("config")

init = require("init")
do_init = init.do_init

schema = require("schema")
do_schema = schema.do_schema

entity = require("entity")
do_entity = entity.do_entity

ledger = require("ledger")
do_ledger = ledger.do_ledger

function main()
    command_funcs = {
        ["init"] = do_init,
        ["schema"] = do_schema,
        ["entity"] = do_entity,
        ["ledger"] = do_ledger,
    }

    arg[-1] = "lua"
    command = arg[1]

    if command != nil then
        arg[0] = "fossci " .. command
    else
        arg[0] = "fossci"
    end

    help_string = get_help_string(arg[0])

    if command == nil or command == "-h" or command == "--help" then
        print(help_string)
        return
    end

    func = command_funcs[command]
    if func == nil then
        print("'" .. command .. "' is not a valid command\n")
        print(help_string)
        return
    end

    cmd_args = {}
    for i = 2, #arg do
        table.insert(cmd_args, arg[i])
    end
    cmd_args[0] = arg[0]

    if command == "init" then
        func(cmd_args)
        return
    end

    if config.is_initialized(".") == false then
        print("Not a fossci store. Run 'fossci init' first.")
        return
    end

    func(cmd_args, config.db_path("."))
end

main()
