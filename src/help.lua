help = {}

HELP_STRING = """
Usage: fossci <command> [subcommand] [arguments]

fossci init                              initialize a fossci store (sqlite db + config)
fossci schema  < add | list | show >     manage entity type definitions
fossci entity  < create | list | show >  create/inspect entities
fossci ledger  < show | history >        inspect the raw event ledger for an entity

defaults:
init   -> initialize .fossci/ in the current directory
schema -> list registered entity types
entity -> list entities of a type
ledger -> show full event history for an entity id
"""

function help.get_help_string(prog)
    return HELP_STRING
end

return help
