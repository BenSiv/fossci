# Manifesto

Commercial electronic lab notebooks and LIMS platforms (Benchling foremost
among them) were built for one discipline first and generalized outward,
if at all. Their data model, their registration workflow, their sense of
what an "entity" is, all still carry the shape of molecular biology: a
sample, a construct, a batch. Labs doing chemistry, materials science,
physics, or anything that doesn't map cleanly onto that shape are left
adapting someone else's ontology to their own work.

fossci starts from the other direction. The only thing it assumes about
your science is that you observe things, you track entities derived from
other entities, and you want an honest record of how you got from one to
the next. Everything domain-specific -- what a "sample" means, what fields
a "batch" schema needs, what a "valid concentration" is -- is defined by
the people using it, in the open, as data and as scriptable rules, not
hardcoded by us.

## What we're committed to

**Traceability is not a feature, it's the foundation.** Every entity
change is an event in an append-only ledger, never an in-place edit.
Every notebook entry, every schema, every extension is a version-controlled
file with real history. If you can't answer "what did we know, and when,
and who changed it" for any record in the system, something has gone
wrong with the architecture, not just the data.

**Structured data belongs in SQL.** A lab record that can't be queried,
joined, and put in front of a dashboard is a record that gets re-entered
into a spreadsheet the first time someone needs to actually analyze it.
The entity ledger and its projected tables are real SQL, on purpose.

**Extensibility is not an afterthought bolted on for enterprise
customers.** It's a first-class part of the platform from day one: schemas,
validation rules, and event hooks are all just scriptable, version-controlled,
user-authored code. The people using the system for their own science are
expected to extend it for their own science, not to file a feature request
and wait.

**Free and open source, all the way down.** Not just the application --
the version control system underneath it, the scripting language
extensions are written in, the database. No part of the stack should be
something a lab has to license, trust blindly, or lose access to if a
vendor changes course. That's the "FOSS" half of the name, and it's not
incidental: it's the same reason we didn't build this on top of a
proprietary ELN in the first place.

**General-purpose, not biology-shaped.** We build on Fossil precisely
because Fossil doesn't know or care what a "sample" is -- it's a version
control and knowledge management substrate. fossci's job is to add
structured entity tracking, experiment planning, and lineage on top of
that substrate for whatever science someone is doing, without smuggling
in assumptions from any one field.

## What "done" looks like

A researcher in any discipline can define what an entity means to them,
record observations and plans in a notebook, register structured entities
directly from that notebook, trust that the full history of every one of
those entities is real and queryable, and extend any part of that
workflow -- validation, automation, integration -- without touching the
platform's own source.
