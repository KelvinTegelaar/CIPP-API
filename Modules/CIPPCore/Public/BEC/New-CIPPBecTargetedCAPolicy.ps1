function New-CIPPBecTargetedCAPolicy {
    <#
    .SYNOPSIS
        Creates a temporary Conditional Access policy that targets one user, and schedules its removal.
    .DESCRIPTION
        The softer alternative to blocking sign-in for a VIP who must keep working: a policy scoped to
        the investigated user that requires MFA (optionally plus a compliant device) for every
        application, enabled or report-only. The policy description carries the case id and expiry,
        a scheduled task runs Remove-CIPPBecTargetedCAPolicy at the expiry, and an existing policy for
        the same user is reused rather than duplicated.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserId
        The user's object id.
    .PARAMETER UserPrincipalName
        The user's UPN (for the display name).
    .PARAMETER State
        enabled or enabledForReportingButNotEnabled.
    .PARAMETER Controls
        mfa, or mfaAndCompliantDevice.
    .PARAMETER ExpiresHours
        Lifetime in hours (1-168).
    .PARAMETER CaseId
        The BEC case id recorded in the description.
    .PARAMETER Headers
        CIPP request headers for logging.
    .PARAMETER APIName
        Logging API name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserId,
        [Parameter(Mandatory = $true)][string]$UserPrincipalName,
        [ValidateSet('enabled', 'enabledForReportingButNotEnabled')][string]$State = 'enabled',
        [ValidateSet('mfa', 'mfaAndCompliantDevice')][string]$Controls = 'mfa',
        [ValidateRange(1, 168)][int]$ExpiresHours = 24,
        [string]$CaseId,
        $Headers,
        [string]$APIName = 'BECRemediate'
    )

    $Tag = "ManagedBy=CIPP-BEC;Target=$UserId"
    $Existing = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?$select=id,displayName,description,state&$top=999' -tenantid $TenantFilter -AsApp $true | Where-Object { [string]$_.description -like "*$Tag*" })
    if ($Existing.Count -gt 0) {
        $Message = "A CIPP BEC containment policy already exists for $UserPrincipalName ('$($Existing[0].displayName)', $($Existing[0].state)); not creating another."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
        return $Message
    }

    $ExpiresUtc = (Get-Date).ToUniversalTime().AddHours($ExpiresHours)
    $DisplayName = "CIPP BEC containment - $UserPrincipalName - expires $($ExpiresUtc.ToString('yyyy-MM-dd HH:mm'))Z"
    $BuiltIn = if ($Controls -eq 'mfaAndCompliantDevice') { @('mfa', 'compliantDevice') } else { @('mfa') }
    $Body = ConvertTo-Json -Depth 10 -InputObject @{
        displayName   = $DisplayName
        state         = $State
        description   = "$Tag;CaseId=$CaseId;ExpiresUtc=$($ExpiresUtc.ToString('o'))"
        conditions    = @{
            users          = @{ includeUsers = @($UserId) }
            applications   = @{ includeApplications = @('All') }
            clientAppTypes = @('all')
        }
        grantControls = @{
            operator        = if ($BuiltIn.Count -gt 1) { 'AND' } else { 'OR' }
            builtInControls = $BuiltIn
        }
    }
    if (-not $PSCmdlet.ShouldProcess($UserPrincipalName, "Create targeted CA policy ($State, $Controls, $ExpiresHours h)")) { return }
    try {
        $Policy = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' -tenantid $TenantFilter -type POST -body $Body -AsApp $true
        $Message = "Created Conditional Access policy '$DisplayName' ($State, $($BuiltIn -join ' + ')) for $UserPrincipalName"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'

        # Expiry: a scheduled removal. The policy name carries the expiry too, so an operator can see it.
        try {
            $Task = [pscustomobject]@{
                TenantFilter  = $TenantFilter
                Name          = "Remove BEC containment CA policy for $UserPrincipalName"
                Command       = @{ value = 'Remove-CIPPBecTargetedCAPolicy'; label = 'Remove-CIPPBecTargetedCAPolicy' }
                Parameters    = [pscustomobject]@{ TenantFilter = $TenantFilter; PolicyId = $Policy.id }
                ScheduledTime = [string][int64]([System.DateTimeOffset]$ExpiresUtc).ToUnixTimeSeconds()
                PostExecution = @{ Webhook = $false; Email = $false; PSA = $false }
                Reference     = $CaseId
            }
            $null = Add-CIPPScheduledTask -Task $Task -Hidden $false -Headers $Headers
            $Message = "$Message; removal scheduled for $($ExpiresUtc.ToString('u'))"
        } catch {
            $Message = "$Message; WARNING: could not schedule its removal ($($_.Exception.Message)) - remove it manually after $($ExpiresUtc.ToString('u'))"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Could not schedule removal of CA policy $($Policy.id): $($_.Exception.Message)" -Sev 'Warning'
        }
        return $Message
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to create the targeted Conditional Access policy for $UserPrincipalName`: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
        throw $Message
    }
}
