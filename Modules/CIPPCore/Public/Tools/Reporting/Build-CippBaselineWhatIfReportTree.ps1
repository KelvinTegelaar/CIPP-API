function Build-CippBaselineWhatIfReportTree {
    <#
    .SYNOPSIS
        Compose the Security Baseline report as a component tree (server port of CippBaselineWhatIfReport.jsx).
    .DESCRIPTION
        Pure composition from already-gathered baseline data: where the baseline stands today, what is
        already in place, the policies and settings it will change (today -> target, and why), the
        rollout waves still to come and the agreed exceptions - plus everything the simulated baselines
        would add. Nothing is changed by producing it. Returns @{ Blocks; Variables }.

        Every helper mirrors the client document's semantics (JS truthiness, `??`, template-literal
        stringification), so the report reads the same whether the inputs are hashtables (the branding
        preview sample) or PSCustomObjects (the live endpoint). Keys match case-sensitively like a JS
        object's: a PSCustomObject's properties are compared with -ceq, and a hashtable matches with its
        own comparer - ConvertFrom-Json -AsHashtable's is case-sensitive, an @{} literal's is not, so a
        caller keying a lookup by data values builds it with an ordinal comparer.
    .PARAMETER Data
        TenantName; tenant (rows[] from Get-CIPPBaselineAlignment); stageStates[]; assignedTemplates[]
        and simulatedTemplates[] (baselines as Get-CIPPBaseline -ResolveIdentityLabels returns them);
        catalog[] (Get-CIPPBaselineDefinition); resolvers (caByGuid / intuneByGuid: stored template
        content keyed by template id); sectionConfig (alreadyAligned / rolloutStages, both default on).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Data)

    # -- JS-semantics helpers. Functions return collections behind a leading comma so an empty or
    # one-item array reaches the caller intact instead of being unrolled to $null or a scalar. --
    function isObj($v) { $v -is [System.Collections.IDictionary] -or $v -is [System.Management.Automation.PSCustomObject] }
    function isArr($v) { $v -is [System.Collections.IList] }
    # A property of a hashtable or PSCustomObject, else $null - a string or array never
    # member-enumerates (JS `x?.key`). PSObject.Properties[$k] ignores case, so the name is
    # compared with -ceq as a JS key would be.
    function pv($o, [string]$k) {
        if ($o -is [System.Collections.IDictionary]) { return , $o[$k] }
        if ($o -is [System.Management.Automation.PSCustomObject]) {
            foreach ($p in $o.PSObject.Properties) { if ($p.Name -ceq $k) { return , $p.Value } }
        }
        $null
    }
    # JS `o[k] !== undefined`: a present null counts as present.
    function has($o, [string]$k) {
        if ($o -is [System.Collections.IDictionary]) { return ([System.Collections.IDictionary]$o).Contains($k) }
        if ($o -is [System.Management.Automation.PSCustomObject]) {
            foreach ($p in $o.PSObject.Properties) { if ($p.Name -ceq $k) { return $true } }
        }
        $false
    }
    function keysOf($o) {
        if ($o -is [System.Collections.IDictionary]) { return , @($o.Keys) }
        if ($o -is [System.Management.Automation.PSCustomObject]) { return , @(foreach ($p in $o.PSObject.Properties) { $p.Name }) }
        , @()
    }
    # JS `[].concat(v ?? [])`.
    function arr($v) { if ($null -eq $v) { return , @() } , @($v) }
    # JS `v?.value ?? v` (legacy saves store option objects {label, value}).
    function unwrap($v) {
        if (isObj $v) {
            $inner = pv $v 'value'
            if ($null -ne $inner) { return , $inner }
        }
        , $v
    }
    function truthy($v) {
        if ($null -eq $v) { return $false }
        if ($v -is [bool]) { return $v }
        if ($v -is [string]) { return $v.Length -gt 0 }
        if ((isArr $v) -or (isObj $v)) { return $true }
        if ($v -is [ValueType]) { try { $n = [double]$v; return ($n -ne 0 -and -not [double]::IsNaN($n)) } catch { return $true } }
        $true
    }
    # JS template-literal stringification (`${v}`): lowercase true/false, invariant numbers, arrays
    # comma-joined, objects '[object Object]', dates as the ISO string the client received.
    function jsStr($v) {
        if ($null -eq $v) { return 'null' }
        if ($v -is [string]) { return $v }
        if ($v -is [bool]) { return $(if ($v) { 'true' } else { 'false' }) }
        if (isArr $v) { return (@(foreach ($x in $v) { if ($null -eq $x) { '' } else { jsStr $x } }) -join ',') }
        if (isObj $v) { return '[object Object]' }
        if ($v -is [datetime] -or $v -is [System.DateTimeOffset]) { return (ConvertTo-Json -InputObject $v -Compress).Trim('"') }
        [System.Convert]::ToString($v, [cultureinfo]::InvariantCulture)
    }
    function orEmpty($v) { if ($null -eq $v) { return '' } jsStr $v }
    function html($s) { [System.Net.WebUtility]::HtmlEncode([string]$s) }
    function plural([int]$c, [string]$s) { if ($c -eq 1) { $s } else { "${s}s" } }

    $Dash = [string][char]0x2014
    $Dot = [string][char]0x00B7
    $Ellipsis = [string][char]0x2026
    $Check = [string][char]0x2714 + [char]0xFE0F

    # -- Inputs --
    $tenant = $Data.tenant
    $rows = arr (pv $tenant 'rows')
    $stageStates = arr $Data.stageStates
    $assignedTemplates = arr $Data.assignedTemplates
    $simulatedTemplates = arr $Data.simulatedTemplates
    $caByGuid = pv $Data.resolvers 'caByGuid'
    $intuneByGuid = pv $Data.resolvers 'intuneByGuid'
    $tenantName = $Data.TenantName ?? (pv $tenant 'displayName') ?? (pv $tenant 'tenantFilter') ?? 'Organization'
    # The catalog keyed by standard name, case-sensitively like the client's object lookup.
    $catalog = [System.Collections.Generic.Dictionary[string, object]]::new()
    foreach ($entry in (arr $Data.catalog)) {
        $name = pv $entry 'name'
        if (truthy $name) { $catalog[(jsStr $name)] = $entry }
    }
    function defOf($base) {
        $found = $null
        if ($null -ne $base -and $catalog.TryGetValue([string]$base, [ref]$found)) { return $found }
        $null
    }

    # -- Report vocabulary (client constants) --
    $changeStatuses = @('Drift', 'Partially Accepted', 'Denied - Remediate Pending', 'Denied - Delete Pending')
    $caFamilies = @('ConditionalAccessTemplate', 'ConditionalAccessTemplatePackage')
    $intuneFamilies = @('IntuneTemplate', 'IntuneTemplatePackage')
    $policyFamilies = @($caFamilies + $intuneFamilies)

    function baseNameOf($standardName) { ([string]$standardName).Split('#')[0].Split('~')[0] }
    function definitionFor($row) { defOf (baseNameOf $row.standardName) }
    function descriptionOf($definition) { orEmpty ((pv $definition 'executiveText') ?? (pv $definition 'helpText')) }

    # How each engine status reads in the current-state table.
    function statusPresentation($status) {
        if ($status -ceq 'Compliant') { return @{ tone = 'pass'; label = 'In place'; order = 0 } }
        if ($changeStatuses -ccontains $status) { return @{ tone = 'warn'; label = 'Being corrected'; order = 1 } }
        if ($status -ceq 'Accepted') { return @{ tone = 'muted'; label = 'Agreed exception'; order = 2 } }
        if ($status -ceq 'No Data') { return @{ tone = 'muted'; label = 'First check pending'; order = 3 } }
        if ($status -ceq 'Failed') { return @{ tone = 'fail'; label = 'Check failed'; order = 4 } }
        if ($status -ceq 'Skipped - No License') { return @{ tone = 'muted'; label = 'License missing'; order = 5 } }
        if ((orEmpty $status).StartsWith('Skipped', [System.StringComparison]::Ordinal)) { return @{ tone = 'muted'; label = 'Not applicable'; order = 5 } }
        @{ tone = 'muted'; label = $(if ($null -eq $status) { 'Unknown' } else { jsStr $status }); order = 6 }
    }

    # What a CA policy protects against, read from its own content.
    function caBenefitPhrases($policy) {
        $phrases = [System.Collections.Generic.List[string]]::new()
        if (-not (isObj $policy)) { return , $phrases }
        $grant = pv $policy 'grantControls'
        $conditions = pv $policy 'conditions'
        $controls = arr (pv $grant 'builtInControls')
        $strength = pv (pv $grant 'authenticationStrength') 'displayName'
        if (truthy $strength) { $phrases.Add("require $(jsStr $strength) (phishing-resistant) sign-in") }
        elseif ($controls -ccontains 'mfa') { $phrases.Add('enforce multi-factor authentication') }
        if ($controls -ccontains 'compliantDevice' -or $controls -ccontains 'domainJoinedDevice') {
            $phrases.Add('only allow access from compliant, company-managed devices')
        }
        if ($controls -ccontains 'passwordChange') { $phrases.Add('force a password change when an account looks compromised') }
        if ($controls -ccontains 'block') { $phrases.Add('block the targeted sign-ins entirely') }
        $locations = pv $conditions 'locations'
        $includeLocations = arr (pv $locations 'includeLocations')
        $excludeLocations = arr (pv $locations 'excludeLocations')
        if (($includeLocations.Count -gt 0 -and $includeLocations -cnotcontains 'All') -or $excludeLocations.Count -gt 0) {
            $phrases.Add('only allow sign-ins from approved locations')
        }
        $clientApps = arr (pv $conditions 'clientAppTypes')
        if ($clientApps -ccontains 'exchangeActiveSync' -or $clientApps -ccontains 'other') {
            $phrases.Add('block legacy sign-in methods that cannot do multi-factor authentication')
        }
        if ((arr (pv $conditions 'signInRiskLevels')).Count -gt 0) { $phrases.Add('respond automatically to risky sign-ins') }
        if ((arr (pv $conditions 'userRiskLevels')).Count -gt 0) { $phrases.Add('respond automatically to accounts marked as at risk') }
        $frequency = pv (pv $policy 'sessionControls') 'signInFrequency'
        if (truthy (pv $frequency 'isEnabled')) {
            $type = pv $frequency 'type'
            $text = 'require signing in again every {0} {1}' -f (orEmpty (pv $frequency 'value')), $(if ($null -eq $type) { 'hours' } else { jsStr $type })
            # The client collapses the first double space only (String.replace with a string pattern).
            $at = $text.IndexOf('  ', [System.StringComparison]::Ordinal)
            if ($at -ge 0) { $text = $text.Remove($at, 1) }
            $phrases.Add($text)
        }
        , $phrases
    }

    # A light, one-line description of what a CA policy does, from its own content.
    function caLightDescription($policy) {
        $phrases = caBenefitPhrases $policy
        if ($phrases.Count -eq 0) { return 'Applies custom sign-in controls.' }
        $text = @($phrases | Select-Object -First 3) -join ', '
        '{0}{1}.' -f $text.Substring(0, 1).ToUpperInvariant(), $text.Substring(1)
    }

    function capJoin($values) {
        $list = @(foreach ($value in (arr $values)) { if (truthy $value) { jsStr $value } })
        if ($list.Count -le 3) { return ($list -join ', ') }
        '{0} +{1} more' -f (@($list[0..2]) -join ', '), ($list.Count - 3)
    }

    # Who a CA policy applies to (or spares), summarised from its users condition.
    function summarizeCaUsers($policy, [string]$kind) {
        $users = pv (pv $policy 'conditions') 'users'
        $parts = [System.Collections.Generic.List[string]]::new()
        $people = arr (pv $users "${kind}Users")
        if ($people -ccontains 'All') { $parts.Add('All users') }
        elseif ($people.Count -gt 0 -and $people -cnotcontains 'None') { $parts.Add((capJoin $people)) }
        $groups = arr (pv $users "${kind}Groups")
        if ($groups.Count -gt 0) { $parts.Add("Groups: $(capJoin $groups)") }
        $roles = arr (pv $users "${kind}Roles")
        if ($roles.Count -gt 0) { $parts.Add("Roles: $(capJoin $roles)") }
        $guests = pv $users "${kind}GuestsOrExternalUsers"
        $guestKeys = if (isArr $guests) { $guests.Count } else { (keysOf $guests).Count }
        if ((truthy $guests) -and (-not ((isObj $guests) -or (isArr $guests)) -or $guestKeys -gt 0)) {
            $parts.Add('Guests / external users')
        }
        if ($parts.Count -eq 0) { return $(if ($kind -eq 'include') { $Dash } else { 'None' }) }
        $parts -join "`n"
    }

    function caStateLabel($state) {
        $value = (orEmpty $state).ToLowerInvariant()
        if ($value -ceq 'enabledforreportingbutnotenforced' -or $value -ceq 'reportonly') {
            return 'in report-only mode first, so we can measure the impact before anyone is blocked'
        }
        if ($value -ceq 'disabled') { return 'switched off until we enable them together' }
        'fully enforced from day one'
    }

    # A rendered displayName that is a real policy name - never a raw template file id, which is what a
    # No Data row's unresolved token render still carries.
    function validName($expectedValue) {
        $rendered = pv $expectedValue 'displayName'
        if ((truthy $rendered) -and (jsStr $rendered) -notmatch '\.json\z') { return (jsStr $rendered) }
        $null
    }

    # The friendly name of a deployed policy: the rendered name, a saved picker label, else the bundle
    # a package instance deploys.
    function policyDisplayName($item) {
        $packageName = (unwrap (pv $item.variables 'caTemplatePackage')) ?? (unwrap (pv $item.variables 'intuneTemplatePackage'))
        $name = (validName $item.expectedValue) ?? (pv (pv $item.variables 'caTemplate') 'label') ?? (pv (pv $item.variables 'intuneTemplate') 'label')
        if ($null -eq $name) {
            $name = if (truthy $packageName) { "Every policy in the '$(jsStr $packageName)' bundle" } else { $item.label }
        }
        orEmpty $name
    }

    function rowPolicyName($row) { orEmpty ((validName $row.expectedValue) ?? $row.standardLabel ?? $row.standardName) }

    function prettifyKey($key) {
        $text = (jsStr $key) -creplace '([a-z0-9])([A-Z])', '$1 $2'
        if ($text.Length -eq 0) { return $text }
        $text.Substring(0, 1).ToUpperInvariant() + $text.Substring(1)
    }

    function prettifyValue($value) {
        if ($value -is [bool]) { return $(if ($value) { 'On' } else { 'Off' }) }
        if (isArr $value) {
            $parts = @(foreach ($x in $value) { $part = prettifyValue $x; if ($null -ne $part) { $part } })
            if ($parts.Count -gt 0) { return ($parts -join ', ') }
            return $null
        }
        if (isObj $value) { return $null }
        jsStr $value
    }

    # A variable's configured value, else the definition's recommended/default; '' counts as unset.
    function resolveVariable($definition, $variables, [string]$name) {
        $declared = pv (pv $definition 'variables') $name
        $value = (unwrap (pv $variables $name)) ?? (pv $declared 'recommended') ?? (pv $declared 'default')
        if ($null -eq $value -or ($value -is [string] -and $value.Length -eq 0)) { return $null }
        , $value
    }

    # A definition's expected block rendered with the baseline's variables. Entries still holding a
    # tenant token (%defaultdomain%) are left out - they resolve per tenant at run time.
    function renderExpected($definition, $variables) {
        $expected = pv $definition 'expected'
        if (-not (truthy $expected)) { return $null }
        $rendered = [ordered]@{}
        foreach ($key in (keysOf $expected)) {
            $template = pv $expected $key
            if ($template -is [string]) {
                if ($template -cmatch '^%([A-Za-z0-9_]+)%\z') {
                    $value = resolveVariable $definition $variables $Matches[1]
                    if ($null -ne $value) { $rendered[$key] = $value }
                    continue
                }
                $replaced = [regex]::Replace($template, '%([A-Za-z0-9_]+)%', {
                        param($match)
                        $value = resolveVariable $definition $variables $match.Groups[1].Value
                        if ($null -eq $value) { $match.Value } else { jsStr $value }
                    })
                if ($replaced -notmatch '%[A-Za-z0-9_]+%') { $rendered[$key] = $replaced }
            } elseif (-not ((isObj $template) -or (isArr $template))) {
                $rendered[$key] = $template
            } elseif (-not (ConvertTo-Json -InputObject $template -Compress -Depth 20).Contains('%')) {
                $rendered[$key] = $template
            }
        }
        if ($rendered.Count -gt 0) { return $rendered }
        $null
    }

    # One "Label: value" line per entry, using the definition's own variable and option labels where an
    # expected key maps to exactly one variable.
    function describeValues($definition, $values) {
        if ($null -eq $values) { return '' }
        if ((isArr $values) -or -not (isObj $values)) { return (prettifyValue $values) ?? 'Configured' }
        $expected = pv $definition 'expected'
        $tokenFor = [System.Collections.Generic.Dictionary[string, string]]::new()
        foreach ($key in (keysOf $expected)) {
            $template = pv $expected $key
            if ($template -is [string] -and $template -cmatch '^%([A-Za-z0-9_]+)%\z') { $tokenFor[$key] = $Matches[1] }
        }
        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($key in (keysOf $values)) {
            $value = pv $values $key
            $variable = if ($tokenFor.ContainsKey($key)) { pv (pv $definition 'variables') $tokenFor[$key] } else { $null }
            $label = (pv $variable 'label') ?? (prettifyKey $key)
            $display = prettifyValue $value
            if ($null -eq $display) {
                $display = @(foreach ($nestedKey in (keysOf $value)) {
                        $nested = prettifyValue (pv $value $nestedKey)
                        if ($null -ne $nested) { '{0}: {1}' -f (prettifyKey $nestedKey), $nested }
                    }) -join ', '
                if (-not $display) { $display = 'configured' }
            }
            $valueText = jsStr $value
            foreach ($option in (arr (pv $variable 'options'))) {
                if ((jsStr (pv $option 'value')) -ceq $valueText) { $display = pv $option 'label'; break }
            }
            if ($display -is [string] -and $display.Length -eq 0) { $display = 'Not set' }
            $parts.Add(('{0}: {1}' -f (jsStr $label), $(if ($null -eq $display) { 'undefined' } else { jsStr $display })))
        }
        if ($parts.Count -gt 8) {
            return (@($parts[0..7]) + "$Ellipsis and $($parts.Count - 8) more values") -join "`n"
        }
        $parts -join "`n"
    }

    function describeChange($definition, $expectedValue) {
        $text = describeValues $definition $expectedValue
        if ($text) { return $text }
        'Enforced as described'
    }

    # What the setting is today, projected onto the keys the baseline cares about so the "from" column
    # shows the relevant values rather than the whole object the API returned.
    function describeToday($definition, $expectedValue, $currentValue) {
        if ($null -eq $currentValue) { return 'Not configured yet' }
        if ((isObj $expectedValue) -and (isObj $currentValue)) {
            $projected = [ordered]@{}
            foreach ($key in (keysOf $expectedValue)) {
                if (has $currentValue $key) { $projected[$key] = pv $currentValue $key }
            }
            if ($projected.Count -gt 0) { return (describeValues $definition $projected) }
        }
        $text = describeValues $definition $currentValue
        if ($text) { return $text }
        'Not configured yet'
    }

    # Why the setting was chosen: who recommends it, which framework requires it, how disruptive it is.
    function describeWhy($definition) {
        $parts = [System.Collections.Generic.List[string]]::new()
        $recommendedBy = @(foreach ($by in (arr (pv $definition 'recommendedBy'))) { if (truthy $by) { jsStr $by } })
        if ($recommendedBy.Count -gt 0) { $parts.Add("Recommended by $($recommendedBy -join ' and ')") }
        foreach ($tag in (arr (pv $definition 'tag'))) {
            if ((jsStr $tag) -match 'CIS|CISA|NIST') { $parts.Add("required for $(jsStr $tag)"); break }
        }
        if ($parts.Count -eq 0) { $parts.Add('Security best practice') }
        $impact = (orEmpty (pv $definition 'impact')).ToLowerInvariant()
        if ($impact) { $parts.Add("$impact change for users") }
        '{0}.' -f ($parts -join '; ')
    }

    # The enforcement content a template instance is configured with: CA/Intune variables hold a
    # template id the resolvers map to stored content; plain settings render their expected block.
    function resolveConfiguredExpected($base, $variables) {
        if ($caFamilies -ccontains $base) {
            $id = unwrap (pv $variables 'caTemplate')
            $content = if ($null -ne $id) { pv $caByGuid (jsStr $id) }
            if (-not (truthy $content)) { return $null }
            $copy = [ordered]@{}
            foreach ($key in (keysOf $content)) { $copy[$key] = pv $content $key }
            $state = unwrap (pv $variables 'state')
            if ((truthy $state) -and -not ($state -is [string] -and $state -ceq 'donotchange')) { $copy['state'] = $state }
            else { $copy['state'] = pv $content 'state' }
            return $copy
        }
        if ($intuneFamilies -ccontains $base) {
            $id = unwrap (pv $variables 'intuneTemplate')
            $content = if ($null -ne $id) { pv $intuneByGuid (jsStr $id) }
            if (-not (truthy $content)) { return $null }
            return [ordered]@{ displayName = (pv $content 'displayName') }
        }
        renderExpected (defOf $base) $variables
    }

    # A No Data row's saved configuration: its own baseline first, then the other assigned ones.
    function configFor($row) {
        $own = @($assignedTemplates | Where-Object { $null -ne $row.templateId -and $_.GUID -ceq $row.templateId })
        $others = @($assignedTemplates | Where-Object { -not ($null -ne $row.templateId -and $_.GUID -ceq $row.templateId) })
        foreach ($template in @($own + $others)) {
            foreach ($stage in (arr $template.stages)) {
                foreach ($candidate in (arr $stage.standardsConfig)) {
                    if (($candidate.instance ?? $candidate.standard) -ceq $row.standardName) { return $candidate }
                }
            }
        }
        $null
    }

    # Everything the baseline will apply: current deviations, standards awaiting their first check
    # (they WILL be enforced - their values come from the baseline's own configuration), and
    # everything the simulated baselines would add.
    $changes = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $rows) {
        if ($changeStatuses -cnotcontains $row.status) { continue }
        $base = baseNameOf $row.standardName
        $changes.Add(@{
                key = $row.standardName; base = $base; label = $row.standardLabel
                expectedValue = $row.expectedValue; currentValue = $row.currentValue; variables = $null
                definition = (defOf $base); simulated = $false; pending = $false
            })
    }
    foreach ($row in $rows) {
        if ($row.status -cne 'No Data') { continue }
        $base = baseNameOf $row.standardName
        $variables = (configFor $row).variables ?? @{}
        # A No Data policy row's expectedValue is the RAW token render (its displayName is still the
        # template file id), so the stored template wins; plain settings keep the engine's render.
        if ($policyFamilies -ccontains $base) { $expectedValue = (resolveConfiguredExpected $base $variables) ?? $row.expectedValue }
        else { $expectedValue = $row.expectedValue ?? (resolveConfiguredExpected $base $variables) }
        $changes.Add(@{
                key = $row.standardName; base = $base; label = $row.standardLabel
                expectedValue = $expectedValue; currentValue = $null; variables = $variables
                definition = (defOf $base); simulated = $false; pending = $true
            })
    }
    $presentNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($row in $rows) { if ($null -ne $row.standardName) { [void]$presentNames.Add([string]$row.standardName) } }
    foreach ($template in $simulatedTemplates) {
        foreach ($stage in (arr $template.stages)) {
            foreach ($instance in (arr $stage.standards)) {
                $instanceKey = [string]$instance
                if ($presentNames.Contains($instanceKey)) { continue }
                if (@($changes | Where-Object { $_.key -ceq $instanceKey }).Count -gt 0) { continue }
                $config = $null
                foreach ($candidate in (arr $stage.standardsConfig)) {
                    if (($candidate.instance ?? $candidate.standard) -ceq $instanceKey) { $config = $candidate; break }
                }
                $base = baseNameOf $instanceKey
                $variables = $config.variables ?? @{}
                $definition = defOf $base
                $changes.Add(@{
                        key = $instanceKey; base = $base; label = (pv $definition 'label') ?? $base
                        expectedValue = (resolveConfiguredExpected $base $variables); currentValue = $null; variables = $variables
                        definition = $definition; simulated = $true; pending = $false; sourceTemplateName = $template.templateName
                    })
            }
        }
    }

    # The client formats in the viewer's timezone; the server uses the instance's (CIPP_TIMEZONE, set at
    # warmup from the configured or region timezone), else UTC. A wave's date is when its stage was
    # entered plus N days, so its time of day is arbitrary and UTC reads a day out for much of the world.
    $reportZone = [TimeZoneInfo]::Utc
    if ($env:CIPP_TIMEZONE) {
        try {
            $reportZone = [TimeZoneInfo]::FindSystemTimeZoneById($env:CIPP_TIMEZONE)
        } catch {
            Write-Information "Baseline report: unknown timezone '$($env:CIPP_TIMEZONE)', dating the waves in UTC"
        }
    }
    function formatAdvanceDate($epoch) {
        if (-not (truthy $epoch)) { return $null }
        try {
            $number = [double]$epoch
            $ms = if ($number -gt 1e12) { $number } else { $number * 1000 }
            [TimeZoneInfo]::ConvertTime([DateTimeOffset]::FromUnixTimeMilliseconds([long]$ms), $reportZone).ToString('MMMM d, yyyy', [cultureinfo]::InvariantCulture)
        } catch { $null }
    }

    # -- Derived values --
    # The current-state table: every standard, what it does, and whether it is correct today.
    $stateRows = @(@(foreach ($row in $rows) {
                $presentation = statusPresentation $row.status
                [pscustomobject]@{
                    name        = (rowPolicyName $row)
                    description = (descriptionOf (definitionFor $row))
                    tone        = $presentation.tone
                    statusLabel = $presentation.label
                    order       = $presentation.order
                }
            }) | Sort-Object -Property @{ Expression = { $_.order } }, @{ Expression = { $_.name } } -Culture 'en-US' -CaseSensitive -Stable)

    $alignedRows = @($rows | Where-Object { $_.status -ceq 'Compliant' })
    $alignedCa = @($alignedRows | Where-Object { $caFamilies -ccontains (baseNameOf $_.standardName) })
    $alignedIntune = @($alignedRows | Where-Object { $intuneFamilies -ccontains (baseNameOf $_.standardName) })
    $alignedSettings = @($alignedRows | Where-Object { $policyFamilies -cnotcontains (baseNameOf $_.standardName) })
    $acceptedRows = @($rows | Where-Object { $_.status -ceq 'Accepted' })
    $pendingCount = @($rows | Where-Object { $_.status -ceq 'No Data' }).Count

    $caChanges = @($changes | Where-Object { $caFamilies -ccontains $_.base })
    $intuneChanges = @($changes | Where-Object { $intuneFamilies -ccontains $_.base })
    $settingChanges = @($changes | Where-Object { $policyFamilies -cnotcontains $_.base })
    # Corrections are drift being fixed; pending items apply once their first check runs and have
    # their own stat card.
    $corrections = @($changes | Where-Object { -not $_.pending })

    function caStateFor($item) { caStateLabel ((pv $item.expectedValue 'state') ?? (unwrap (pv $item.variables 'state'))) }
    $caStates = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $caChanges) { $state = caStateFor $item; if (-not $caStates.Contains($state)) { $caStates.Add($state) } }
    $simulatedNames = @(foreach ($template in $simulatedTemplates) { orEmpty $template.templateName })

    # The rollout, one bullet per wave, in plain words - what each wave holds and when the next one
    # lands. Never the raw graduation conditions.
    $waveBullets = [System.Collections.Generic.List[object]]::new()
    foreach ($state in $stageStates) {
        $prefix = if ($stageStates.Count -gt 1) { "$(orEmpty $state.templateName) $Dash " } else { '' }
        $liveCount = @($rows | Where-Object { -not (truthy $_.templateId) -or -not (truthy $state.templateId) -or $_.templateId -ceq $state.templateId }).Count
        $stageName = if (truthy $state.stageName) { " ('$(jsStr $state.stageName)')" } else { '' }
        $waveBullets.Add(@{
                label = ('{0}Wave {1} of {2}{3}:' -f $prefix, (jsStr $state.currentStage), (jsStr ($state.totalStages ?? $state.currentStage)), $stageName)
                text  = ('live now{0}.' -f $(if ($liveCount -gt 0) { ", covering $liveCount $(plural $liveCount 'protection')" }))
            })
        if (truthy $state.nextStage) {
            $upcoming = arr $state.nextStage.standards
            $names = @(foreach ($key in @($upcoming | Select-Object -First 3)) { orEmpty ((pv (defOf (baseNameOf $key)) 'label') ?? (baseNameOf $key)) })
            $date = formatAdvanceDate $state.estimatedAdvanceAt
            $text = 'adds {0}' -f $(if ($upcoming.Count -gt 0) { "$($upcoming.Count) more $(plural $upcoming.Count 'protection')" } else { 'further protections' })
            if ($names.Count -gt 0) { $text = '{0} - {1}{2}' -f $text, ($names -join ', '), $(if ($upcoming.Count -gt $names.Count) { ' and more' }) }
            $text = '{0}. {1}{2}.' -f $text, $(if ($date) { "Expected around $date" } else { 'Deploys once the current wave has settled in' }), $(if (truthy $state.manualAdvance) { ', after we approve the move together' })
            $nextName = if (truthy $state.nextStageName) { " ('$(jsStr $state.nextStageName)')" } else { '' }
            $waveBullets.Add(@{
                    label = ('{0}Wave {1}{2}:' -f $prefix, (jsStr ($state.currentStage + 1)), $nextName)
                    text  = $text
                })
        }
    }

    # Section toggles are on unless explicitly false (the client's `!== false`).
    $alreadyAligned = pv $Data.sectionConfig 'alreadyAligned'
    $rolloutStages = pv $Data.sectionConfig 'rolloutStages'
    $fullyAligned = $rows.Count -gt 0 -and $changes.Count -eq 0 -and $pendingCount -eq 0 -and $simulatedTemplates.Count -eq 0
    $showAligned = -not ($alreadyAligned -is [bool] -and -not $alreadyAligned) -and ($alignedCa.Count + $alignedIntune.Count + $alignedSettings.Count) -gt 0
    $showStages = -not ($rolloutStages -is [bool] -and -not $rolloutStages) -and $waveBullets.Count -gt 0

    # Both CA tables share one row shape: the policy, what it lightly does, who it includes and excludes.
    $caColumns = @(
        @{ header = 'Policy'; key = 'policy'; width = 1.5; bold = $true }
        @{ header = 'What it does'; key = 'does'; width = 2.3 }
        @{ header = 'Applies to'; key = 'includes'; width = 1.3 }
        @{ header = 'Excluded'; key = 'excludes'; width = 1.3 }
    )
    $simulatedFootnote = "* added by a simulated baseline ($($simulatedNames -join ', '))."

    $blocks = [System.Collections.Generic.List[object]]::new()

    # -- Executive Summary --
    $blocks.Add((New-CippReportPage -Title 'Executive Summary' -Subtitle 'What is protecting you today, and what we will improve next'))
    $simulatedSentence = if ($simulatedNames.Count -gt 0) {
        '. It also shows everything the following baseline{0} would add: {1}' -f $(if ($simulatedNames.Count -ne 1) { 's' }), (html ($simulatedNames -join ', '))
    } else { '' }
    $blocks.Add((New-CippReportParagraph -Html ('<p>Your environment is protected by a <b>managed security baseline</b>: an agreed set of security policies and settings that we deploy, check continuously, and repair when anything drifts out of line. This report shows where that baseline stands today, what we will change next, and why each choice was made{0}.</p>' -f $simulatedSentence)))
    $blocks.Add((New-CippReportStatRow -Stats @(
                @{ value = "$($alignedRows.Count)"; label = 'In Place' }
                @{ value = "$($corrections.Count)"; label = 'Being Improved' }
                @{ value = "$pendingCount"; label = 'First Check Pending' }
                @{ value = "$($acceptedRows.Count)"; label = 'Agreed Exceptions' }
            )))
    if ($fullyAligned) {
        $blocks.Add((New-CippReportClearBox -Title "$Check Fully aligned" -Content 'Every part of the baseline is in effect and verified. We keep checking on every run, and anything that drifts is corrected automatically.'))
    }
    $blocks.Add((New-CippReportParagraph -Title 'Where The Baseline Stands Today' -Html '<p>Every protection in the baseline is listed below with its current state. <b>In place</b> means it is deployed and verified as correct. <b>Being corrected</b> means it drifted from the agreed value and is covered in the changes on the next pages. <b>First check pending</b> means it was recently assigned - what it will apply is already listed in the changes on the next pages, and the first verification run confirms it.</p>'))
    $blocks.Add((New-CippReportTable -Limit 150 -EmptyText 'The baseline was just assigned - the first verification run has not completed yet.' -Columns @(
                @{ header = 'Protection'; key = 'name'; width = 1.7; bold = $true }
                @{ header = 'What it does'; key = 'description'; width = 2.9 }
                @{ header = 'Status'; key = 'statusLabel'; width = 1; toneField = 'tone' }
            ) -Rows @(foreach ($stateRow in $stateRows) {
                    @{ name = $stateRow.name; description = $stateRow.description; statusLabel = $stateRow.statusLabel; tone = $stateRow.tone }
                })))

    # -- What Is Already In Place: policies by name and content, settings with their enforced values --
    if ($showAligned) {
        $blocks.Add((New-CippReportPage -Title 'What Is Already In Place' -Subtitle 'Deployed, verified, and re-checked on every run'))
        if ($alignedCa.Count -gt 0) {
            $blocks.Add((New-CippReportParagraph -Title 'Conditional Access Policies In Force' -Text 'The following Conditional Access policies are deployed and verified:'))
            $blocks.Add((New-CippReportTable -Columns $caColumns -Limit 50 -Rows @(foreach ($row in $alignedCa) {
                            @{
                                policy   = (rowPolicyName $row)
                                does     = (caLightDescription $row.expectedValue)
                                includes = (summarizeCaUsers $row.expectedValue 'include')
                                excludes = (summarizeCaUsers $row.expectedValue 'exclude')
                            }
                        })))
        }
        if ($alignedIntune.Count -gt 0) {
            $blocks.Add((New-CippReportParagraph -Title 'Intune Policies In Force' -Text 'The following Intune policies are deployed and keeping your devices configured to the agreed standard:'))
            $blocks.Add((New-CippReportBullets -Items @(foreach ($row in $alignedIntune) {
                            @{ label = (orEmpty ((pv $row.expectedValue 'displayName') ?? $row.standardLabel)); text = '' }
                        })))
        }
        if ($alignedSettings.Count -gt 0) {
            $blocks.Add((New-CippReportTable -Title 'Settings Enforced Today' -Limit 150 -Columns @(
                        @{ header = 'Setting'; key = 'setting'; width = 1.4; bold = $true }
                        @{ header = 'What it does'; key = 'description'; width = 2.4 }
                        @{ header = 'Set to'; key = 'value'; width = 1.5 }
                        @{ header = 'Why'; key = 'why'; width = 1.4 }
                    ) -Rows @(foreach ($row in $alignedSettings) {
                            $definition = definitionFor $row
                            @{
                                setting     = (orEmpty $row.standardLabel)
                                description = (descriptionOf $definition)
                                value       = (describeChange $definition ($row.currentValue ?? $row.expectedValue))
                                why         = (describeWhy $definition)
                            }
                        })))
        }
    }

    # -- Policies We Will Deploy --
    if ($caChanges.Count -gt 0 -or $intuneChanges.Count -gt 0) {
        $blocks.Add((New-CippReportPage -Title 'Policies We Will Deploy' -Subtitle 'New protection rolling out, and what it adds'))
        if ($caChanges.Count -gt 0) {
            $blocks.Add((New-CippReportParagraph -Title 'Conditional Access Policies' -Text 'We will deploy the following Conditional Access policies, which control who can sign in, from where, and under what conditions:'))
            $blocks.Add((New-CippReportTable -Columns $caColumns -Limit 50 -Rows @(foreach ($item in $caChanges) {
                            @{
                                policy   = ('{0}{1}' -f (policyDisplayName $item), $(if ($item.simulated) { ' *' }))
                                does     = ('{0}{1}' -f (caLightDescription $item.expectedValue), $(if ($caStates.Count -gt 1) { " Deployed $(caStateFor $item)." }))
                                includes = (summarizeCaUsers $item.expectedValue 'include')
                                excludes = (summarizeCaUsers $item.expectedValue 'exclude')
                            }
                        })))
            if ($caStates.Count -eq 1) {
                $blocks.Add((New-CippReportParagraph -Html ('<p>These policies will be deployed <b>{0}</b>.</p>' -f (html $caStates[0]))))
            }
            if (@($caChanges | Where-Object { $_.simulated }).Count -gt 0) {
                $blocks.Add((New-CippReportParagraph -Text $simulatedFootnote))
            }
        }
        if ($intuneChanges.Count -gt 0) {
            $blocks.Add((New-CippReportParagraph -Title 'Intune Policies' -Text 'We will implement the following Intune policies:'))
            $blocks.Add((New-CippReportBullets -Items @(foreach ($item in $intuneChanges) {
                            @{ label = (policyDisplayName $item); text = $(if ($item.simulated) { "(added by the '$(orEmpty $item.sourceTemplateName)' baseline)" } else { '' }) }
                        })))
            $blocks.Add((New-CippReportParagraph -Text 'These policies configure and protect the devices your staff work on, so every device meets the same security bar before it touches company data.'))
        }
    }

    # -- Settings We Will Change --
    if ($settingChanges.Count -gt 0) {
        $blocks.Add((New-CippReportPage -Title 'Settings We Will Change' -Subtitle 'Each setting: what it does, what it is today, what we set it to, and why'))
        $blocks.Add((New-CippReportTable -Limit 150 -Columns @(
                    @{ header = 'Setting'; key = 'setting'; width = 1.3; bold = $true }
                    @{ header = 'What it does'; key = 'description'; width = 2.1 }
                    @{ header = 'Today'; key = 'today'; width = 1.3 }
                    @{ header = 'We will set it to'; key = 'change'; width = 1.4 }
                    @{ header = 'Why'; key = 'why'; width = 1.3 }
                ) -Rows @(foreach ($item in $settingChanges) {
                        @{
                            setting     = ('{0}{1}' -f (orEmpty $item.label), $(if ($item.simulated) { ' *' }))
                            description = (descriptionOf $item.definition)
                            today       = $(if ($item.pending) { 'Not checked yet' } elseif ($item.simulated) { $Dash } else { describeToday $item.definition $item.expectedValue $item.currentValue })
                            change      = (describeChange $item.definition $item.expectedValue)
                            why         = (describeWhy $item.definition)
                        }
                    })))
        if (@($settingChanges | Where-Object { $_.simulated }).Count -gt 0) {
            $blocks.Add((New-CippReportParagraph -Text $simulatedFootnote))
        }
    }

    # -- Rollout Plan --
    if ($showStages -or $acceptedRows.Count -gt 0) {
        $blocks.Add((New-CippReportPage -Title 'Rollout Plan' -Subtitle 'How the changes arrive, and agreed exceptions'))
        if ($showStages) {
            $blocks.Add((New-CippReportParagraph -Title 'How The Rollout Works' -Text 'The baseline is deployed in waves rather than all at once, so your team never faces every change on the same day. Each wave is monitored until it has proven stable before the next one begins.'))
            $blocks.Add((New-CippReportBullets -Items @($waveBullets)))
        }
        if ($acceptedRows.Count -gt 0) {
            $blocks.Add((New-CippReportParagraph -Title 'Agreed Exceptions We Will Not Change' -Text 'These deviations from the baseline were reviewed and accepted, so they stay as they are:'))
            $blocks.Add((New-CippReportBullets -Items @(foreach ($row in $acceptedRows) {
                            @{ label = (orEmpty $row.standardLabel); text = $(if (truthy $row.deviationReason) { "$Dash $(jsStr $row.deviationReason)" } else { '' }) }
                        })))
        }
    }

    $meta = [System.Collections.Generic.List[string]]::new()
    $meta.Add("$($alignedRows.Count) $(plural $alignedRows.Count 'protection') in place")
    $meta.Add("$($corrections.Count) $(plural $corrections.Count 'improvement') underway")
    if ($pendingCount -gt 0) { $meta.Add("$pendingCount applying after $(if ($pendingCount -eq 1) { 'its' } else { 'their' }) first check") }
    # covertitle/coveraccent are explicit: the kit would otherwise split the report name on its last word.
    $variables = @{
        coverlabel         = 'Security Baseline'
        covertitle         = 'Baseline'
        coveraccent        = 'Report'
        coversubtitle      = 'The security protections in place today, the improvements rolling out next, and the reasons behind each choice.'
        covermeta          = $meta -join " $Dot "
        coverfallbackimage = '/reportImages/soc.jpg'
        footerlabel        = "$tenantName $Dash Security Baseline"
    }
    if ($simulatedNames.Count -gt 0) { $variables.covermetanote = "Includes a simulation of: $($simulatedNames -join ', ')" }

    @{
        Blocks    = @($blocks)
        Variables = $variables
    }
}
