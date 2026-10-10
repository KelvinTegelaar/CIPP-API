function Get-CIPPBecTransportRules {
    <#
    .SYNOPSIS
        Collects transport-rule changes in the window and the current transport rules that divert or suppress mail.
    .DESCRIPTION
        Attackers add a BCC/redirect/delete transport rule to keep a feed after the mailbox itself is
        cleaned, so this is tenant-wide. Changes come from the unified audit log (New/Set/Enable/Disable/
        Remove-TransportRule, attributed to the actor and client IP) and are flagged when a risky action
        parameter was set. The current rules are read with Get-TransportRule and flagged on their
        structured action properties (BlindCopyTo, RedirectMessageTo, DeleteMessage, Quarantine, SetSCL
        ...) and on the description text; only flagged rules are returned, with the total count.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER StartDate
        Window start (UTC).
    .PARAMETER EndDate
        Window end (UTC).
    .PARAMETER Heuristics
        The BEC heuristics object (transportRules section, caps).
    .PARAMETER Anchor
        Anchor mailbox for the EXO requests.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][datetime]$StartDate,
        [Parameter(Mandatory = $true)][datetime]$EndDate,
        [Parameter(Mandatory = $true)]$Heuristics,
        [string]$Anchor
    )

    # riskyParameterRegex: diversion/interception actions, always flagged. recentParameterRegex: suppression
    # actions (delete, quarantine, SCL, headers) that admins use legitimately - flagged only on rules changed
    # in the window (every audited change is in the window by definition).
    $ParamRegex = [string]$Heuristics.transportRules.riskyParameterRegex
    $RecentRegex = [string]$Heuristics.transportRules.recentParameterRegex
    $DescriptionRegex = [string]$Heuristics.transportRules.descriptionRegex
    $MatchesAny = { param($Name, [bool]$Recent) ($ParamRegex -and $Name -match $ParamRegex) -or ($Recent -and $RecentRegex -and $Name -match $RecentRegex) }
    $Operations = @($Heuristics.transportRules.operations)
    $MaxPages = [int]($Heuristics.caps.auditLogPages ?? 10)

    $HasValue = { param($Value) if ($null -eq $Value) { $false } elseif ($Value -is [bool]) { $Value } elseif ($Value -is [string]) { -not [string]::IsNullOrWhiteSpace($Value) -and $Value -ne 'False' } elseif ($Value -is [System.Collections.IEnumerable]) { @($Value | Where-Object { $_ }).Count -gt 0 } else { [string]$Value -notin @('', '0', 'False') } }

    # Changes in the window
    $Changes = try {
        $Search = Search-CIPPBecAuditLog -TenantFilter $TenantFilter -StartDate $StartDate -EndDate $EndDate -Operations $Operations -RecordType 'ExchangeAdmin' -Anchor $Anchor -MaxPages $MaxPages
        $Rows = foreach ($Record in $Search.Records) {
            $AD = $Record.AuditData
            if (-not $AD) { continue }
            $Params = @($AD.Parameters | Where-Object { $_ -and $_.Name })
            $RuleName = ($Params | Where-Object { $_.Name -eq 'Name' } | Select-Object -First 1).Value ?? ($Params | Where-Object { $_.Name -eq 'Identity' } | Select-Object -First 1).Value ?? $AD.ObjectId
            $Risky = @($Params | Where-Object { (& $MatchesAny $_.Name $true) -and (& $HasValue $_.Value) } | ForEach-Object { $_.Name })
            $Described = @($Params | Where-Object { $_.Name -notin @('Identity', 'Name') } | ForEach-Object {
                    $Value = [string]$_.Value
                    if ($Value.Length -gt 200) { $Value = $Value.Substring(0, 200) + '...' }
                    "$($_.Name)=$Value"
                })
            [pscustomobject]@{
                Operation       = $AD.Operation
                Date            = $AD.CreationTime
                Actor           = $AD.UserId
                ClientIP        = ConvertTo-CIPPBecHostAddress -Address ($AD.ClientIP ?? $AD.ClientIPAddress)
                RuleName        = [string]$RuleName
                Parameters      = ($Described -join '; ')
                RiskyParameters = $Risky
                Flagged         = ($Risky.Count -gt 0 -and $AD.Operation -in @('New-TransportRule', 'Set-TransportRule', 'Enable-TransportRule'))
                AuditData       = $AD
            }
        }
        $Rows = @($Rows | Sort-Object -Property @{ Expression = { $_.Flagged }; Descending = $true }, @{ Expression = { $_.Date }; Descending = $true })
        New-CIPPBecCollectorResult -Data $Rows -Complete $Search.Complete -Cap $Search.Cap -Count $Rows.Count
    } catch {
        New-CIPPBecCollectorResult -Data @() -Error "Transport rule audit search failed: $((Get-NormalizedError -message $_.Exception.Message))"
    }

    # Current rules
    $Flagged = try {
        $Rules = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-TransportRule' -cmdParams @{ ResultSize = 'Unlimited' } -Anchor $Anchor | Where-Object { $_ })
        $Rows = foreach ($Rule in $Rules) {
            $ChangedInWindow = [bool]($Rule.WhenChanged -and ([datetime]$Rule.WhenChanged).ToUniversalTime() -ge $StartDate.ToUniversalTime())
            $Reasons = [System.Collections.Generic.List[string]]::new()
            foreach ($Property in $Rule.PSObject.Properties) {
                if ((& $MatchesAny $Property.Name $ChangedInWindow) -and (& $HasValue $Property.Value)) {
                    $Value = [string](@($Property.Value) -join ', ')
                    if ($Value.Length -gt 200) { $Value = $Value.Substring(0, 200) + '...' }
                    $Reasons.Add("$($Property.Name) = $Value")
                }
            }
            # a rule is flagged on what it does, never on its description alone
            if ($Reasons.Count -eq 0) { continue }
            if ($ChangedInWindow) { $Reasons.Add('Changed within the investigation window') }
            if ($DescriptionRegex -and [string]$Rule.Description -match $DescriptionRegex) { $Reasons.Add('Description mentions a routing or disposition action') }
            if ($Rule.Mode -and $Rule.Mode -ne 'Enforce') { $Reasons.Add("Rule is in $($Rule.Mode) mode") }
            if ($Rule.State -eq 'Disabled') { $Reasons.Add('Rule is disabled') }
            $Description = [string]$Rule.Description
            if ($Description.Length -gt 500) { $Description = $Description.Substring(0, 500) + '...' }
            [pscustomobject]@{
                Identity    = [string]$Rule.Identity
                Guid        = [string]$Rule.Guid
                Name        = $Rule.Name
                State       = $Rule.State
                Mode        = $Rule.Mode
                Priority    = $Rule.Priority
                WhenChanged = $Rule.WhenChanged
                ChangedInWindow = $ChangedInWindow
                RiskReasons = $Reasons.ToArray()
                Description = $Description
                Flagged     = $true
            }
        }
        New-CIPPBecCollectorResult -Data @($Rows | Sort-Object -Property @{ Expression = { $_.ChangedInWindow }; Descending = $true }, Name)
    } catch {
        New-CIPPBecCollectorResult -Data @() -Error "Get-TransportRule failed: $((Get-NormalizedError -message $_.Exception.Message))"
    }

    return [pscustomobject]@{
        Changes = $Changes
        Flagged = $Flagged
    }
}
