function Test-CIPPCAGapCaImmuneResources {
    <#
    .SYNOPSIS
        Tenant-wide awareness finding about Microsoft resources that Conditional Access never evaluates.
    .DESCRIPTION
        When at least one enabled or report-only policy targets All cloud apps, emits a single Info finding
        listing the resources that always show notApplied in sign-in logs (Intune Checkin, Windows
        Notification Service, Mobile Application Management, Azure MFA Connector, OCaaS Client Interaction
        Service, Authenticator App).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()
    $AllAppsPolicies = @($Context.Policies | Where-Object { $_.state -ne 'disabled' -and (@($_.conditions.applications.includeApplications) -contains 'All') })
    if ($AllAppsPolicies.Count -eq 0) { return @($Findings) }

    $Resources = @($Context.Data.ImmuneResources)
    $Names = @($Resources | ForEach-Object { "$($_.displayName)" }) -join ', '
    $Params = @{
        Severity         = 'Info'
        Category         = 'Always-exempt services'
        Title            = "$($Resources.Count) Microsoft services are never subject to Conditional Access"
        Description      = "Although $($AllAppsPolicies.Count) of your policies cover every application, Microsoft exempts these services by design: $Names. Sign-ins to them are recorded as not evaluated, and they can be used to test whether a password is valid without triggering any policy."
        Remediation      = 'Nothing can change this. Watch sign-in activity against these services for signs of password testing.'
        AffectedPolicies = @($AllAppsPolicies | ForEach-Object { $_.displayName })
        RelatedIds       = @($Resources | ForEach-Object { "$($_.resourceId)" })
    }
    $Findings.Add((New-CIPPCAGapFinding @Params))

    @($Findings)
}
