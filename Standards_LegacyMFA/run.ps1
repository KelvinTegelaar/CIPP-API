param($tenant)

try {
    #nothing yet.
}
catch {
    Log-request "Standards API: $($tenant) failed to apply mailbox retention. Error: $($exception.message)" -sev Error
}