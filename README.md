# Actually

Actually is Bolty's private Ascension guild utility add-on.

Guild-restricted feature behavior is configured explicitly in
`data/FeatureSwitches.lua`. Each protected feature can be `enabled`, `disabled`,
or set to return a controlled `error` outside the allowed-guild list.

## Useful commands

* `/act user list` shows detected Actually users and their current guild, or
  `Unguilded` when the roster API confirms that they have no guild.
* `/act arc commands` opens the ARC Commander plan editor. Each saved command
  can be configured as Enabled, Disabled, or Error on press.

## Licensing

Copyright (c) 2026 Bolty. Actually is proprietary software. Installation and
personal use of unmodified copies supplied by the copyright holder are
permitted; copying, modification, or redistribution requires prior written
permission. See `LICENSE`.

Separately licensed embedded libraries retain their own rights and required
notices in `THIRD_PARTY_NOTICES.md`.
