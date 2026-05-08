## Rails 7.2.1 ##

*   Fix `insert_all` log message when called on anonymous classes.

    *Gabriel Sobrinho*

*   Restore previous instrumenter after `execute_or_skip`.

    *Rosa Gutierrez*

*   Fix encoding errors for non-ASCII string locals.

    *Hammad Khan*


## Rails 7.2.0 ##

*   Add structured events for Active Record.

*   Backport Active Record normalization to Active Model attributes.

*   Support virtual generated columns on PostgreSQL 18+.
