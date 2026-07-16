function Get-CIPPTestData {
    <#
    .SYNOPSIS
        Cached wrapper around New-CIPPDbRequest for test functions

    .DESCRIPTION
        Returns cached tenant data during test suite execution. The cache is backed by
        CIPP.TestDataCache (static ConcurrentDictionary in C#) so it is shared across all
        PowerShell runspaces within the worker process.

        RECORDS ARE FIELD-PROJECTED. Only the fields listed for $Type in
        Get-CippTestDataFieldManifest are materialized. Reading an unlisted field returns $null
        with no error, so the test emits a wrong verdict silently. If you add a field read to a
        test, add it to the manifest first. A type absent from the manifest is fetched whole,
        which is the safe default.

        Projection is record-level: a kept field keeps its entire subtree, so
        `$policy.conditions.users.includeRoles` only requires 'conditions'.

        Records are PSCustomObject and must stay so. Hashtable output changes scalar semantics
        ($x[0] becomes a key lookup returning $null; $x.Count returns the record's field count
        instead of 1) and only when a pipeline yields exactly one record — data-dependent, and
        easily missed in testing.

    .PARAMETER TenantFilter
        The tenant domain or GUID to filter by

    .PARAMETER Type
        The data type to retrieve (e.g., Users, Groups, ConditionalAccessPolicies)

    .PARAMETER Fields
        Optional. Override the manifest for this call: keep only these top-level fields. Prefer
        the manifest; this is for one-off and diagnostic callers, not tests.

        The field set is part of the cache key — it must be, or callers asking for the same
        tenant+type with different lists would receive each other's projection. Distinct lists
        therefore fragment the cache: the same rows parsed once per list, all alive together for
        the TTL. Per-call-site lists measured several times worse than one shared per-type entry.
        Fields belong to the type — see Get-CippTestDataFieldManifest.

    .PARAMETER NoProjection
        Return every field, ignoring the manifest.

        Required for the custom-script sandbox (Get-CippSandboxData): those scripts are
        customer-authored, so the fields they read are unknowable and a manifest built from our
        own tests would silently hand them incomplete records. Any caller fetching data on behalf
        of code we did not write must pass this.

    .EXAMPLE
        Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'
        Normal use: the manifest decides the fields. This is what tests should do.

    .EXAMPLE
        Get-CIPPTestData -TenantFilter $Tenant -Type 'Users' -NoProjection
        Every field. For callers serving code we did not author.

    .NOTES
        Verifying a change: "0 errored" proves nothing, because the failure modes here are silent
        — a broken test still reports success. Diff test verdicts against a baseline, across more
        than one tenant: a bug that needs exactly one matching record will not show on a tenant
        that has two.

        Useful endpoints: ExecTestRun then ListTests for verdicts; ListDBCache to confirm a field
        exists and its real casing before adding it to the manifest (type=_availableTypes lists
        the types); ListWorkerHealth?Action=CacheDiag for entries, hit rate and a per-type
        breakdown whose keys carry the projected field list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string]$Type,

        [Parameter(Mandatory = $false)]
        [string[]]$Fields,

        [Parameter(Mandatory = $false)]
        [switch]$NoProjection
    )

    # Enforce tenant lock when running inside custom script execution
    if ($script:CIPPLockedTenant) {
        $TenantFilter = $script:CIPPLockedTenant
    }

    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
        throw 'TenantFilter is required.'
    }

    # Resolve the field set: an explicit -Fields wins, otherwise consult the per-type manifest.
    # -NoProjection suppresses both (the sandbox path must never receive projected records).
    $EffectiveFields = if ($NoProjection) {
        $null
    } elseif ($Fields) {
        $Fields
    } else {
        Get-CippTestDataFieldManifest -Type $Type
    }

    # Normalize the field set (sorted + de-duplicated) so that callers asking for the same
    # fields in a different order share one cache entry instead of parsing twice.
    $NormalizedFields = if ($EffectiveFields) { @($EffectiveFields | Sort-Object -Unique) } else { $null }

    $CacheKey = if ($NormalizedFields) {
        '{0}|{1}|{2}' -f $TenantFilter, $Type, ($NormalizedFields -join ',')
    } else {
        '{0}|{1}' -f $TenantFilter, $Type
    }

    $CachedValue = $null
    if ([CIPP.TestDataCache]::TryGet($CacheKey, [ref]$CachedValue)) {
        return $CachedValue
    }

    $Data = if ($NormalizedFields) {
        New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Type -Fields $NormalizedFields
    } else {
        New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Type
    }

    [CIPP.TestDataCache]::Set($CacheKey, $Data)

    return $Data
}
