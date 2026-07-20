# Change receipt

- Production diagnosis: CH01-CH08 class boundary was absent; stored evidence JPEGs were normal.
- AI behavior: confidence filtering remains unchanged; channel allowlist is applied after confidence filtering and before metadata publication.
- Frontend behavior: alarm-time evidence is fetched again for same-alarm reopen and errors are visible.
- Database cleanup: authorized only when `CONFIRM_CLEAR_MESSAGES=YES`; data-only SQL backup is verified before delete.
- Rollback: restores source, runtime files, environment files, web assets, service state and cleared database records.
