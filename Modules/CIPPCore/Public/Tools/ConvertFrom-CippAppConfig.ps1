function ConvertFrom-CippAppConfig {
    <#
    .SYNOPSIS
        Parses an Intune app template's per-app config, tolerating older templates that carry two
        spellings of the same key ('AssignTo' and 'assignTo').
    .DESCRIPTION
        ConvertFrom-Json maps JSON onto a PSObject, whose members are case-insensitive, so it
        throws outright when one object holds two names differing only by case:

            Cannot convert the JSON string because it contains keys with different casing.
            Please use the -AsHashTable switch instead. The key that was attempted to be added
            to the existing key 'AssignTo' was 'assignTo'.

        -AsHashTable, which that message recommends, is not a fix on its own - it returns BOTH
        keys, so collapsing them into any case-insensitive dictionary resolves last-key-wins. That
        is the worse failure: a stale 'assignTo' of 'On' silently beats the 'AssignTo' the operator
        picked and the app deploys unassigned, with no error anywhere.

        So collapse deliberately: on a collision the canonical spelling wins, unless it is the one
        carrying no value.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Json
    )

    begin {
        # Canonical casing, matching the template editor form field names in
        # CippAppTemplateDrawer.jsx - that form is the source of truth for a config.
        $CanonicalKeys = @('AssignTo', 'customGroup', 'excludeGroup', 'applicationName')
    }

    process {
        if ([string]::IsNullOrWhiteSpace($Json)) { return $null }

        $Parsed = $Json | ConvertFrom-Json -Depth 100 -AsHashtable
        $Config = [ordered]@{}

        foreach ($Key in $Parsed.Keys) {
            # $Config is case-insensitive, so Contains() hits on a key already present under a
            # different casing. Keep what is there unless the incoming one is the canonical
            # spelling AND actually has a value.
            if ($Config.Contains($Key)) {
                $IsCanonical = $Key -cin $CanonicalKeys
                $IsEmpty = [string]::IsNullOrWhiteSpace([string]$Parsed[$Key])
                if (-not $IsCanonical -or $IsEmpty) { continue }
            }
            $Config[$Key] = $Parsed[$Key]
        }

        return [PSCustomObject]$Config
    }
}
