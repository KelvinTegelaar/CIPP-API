using namespace System.Net

function Invoke-EditSafeLinksPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
    .DESCRIPTION
        This function modifies an existing Safe Links policy.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $PolicyName = $Request.Query.PolicyName ?? $Request.Body.PolicyName

    # Extract all possible parameters from body
    $EnableSafeLinksForEmail = $Request.Body.EnableSafeLinksForEmail
    $EnableSafeLinksForTeams = $Request.Body.EnableSafeLinksForTeams
    $EnableSafeLinksForOffice = $Request.Body.EnableSafeLinksForOffice
    $TrackClicks = $Request.Body.TrackClicks
    $AllowClickThrough = $Request.Body.AllowClickThrough
    $ScanUrls = $Request.Body.ScanUrls
    $EnableForInternalSenders = $Request.Body.EnableForInternalSenders
    $DeliverMessageAfterScan = $Request.Body.DeliverMessageAfterScan
    $DisableUrlRewrite = $Request.Body.DisableUrlRewrite
    $DoNotRewriteUrls = $Request.Body.DoNotRewriteUrls
    $AdminDisplayName = $Request.Body.AdminDisplayName
    $CustomNotificationText = $Request.Body.CustomNotificationText
    $EnableOrganizationBranding = $Request.Body.EnableOrganizationBranding

    try {
        # Build command parameters dynamically based on what's provided
        $cmdParams = @{
            Identity = $PolicyName
        }

        # Only add parameters that are explicitly provided
        if ($null -ne $EnableSafeLinksForEmail) { $cmdParams.Add('EnableSafeLinksForEmail', $EnableSafeLinksForEmail) }
        if ($null -ne $EnableSafeLinksForTeams) { $cmdParams.Add('EnableSafeLinksForTeams', $EnableSafeLinksForTeams) }
        if ($null -ne $EnableSafeLinksForOffice) { $cmdParams.Add('EnableSafeLinksForOffice', $EnableSafeLinksForOffice) }
        if ($null -ne $TrackClicks) { $cmdParams.Add('TrackClicks', $TrackClicks) }
        if ($null -ne $AllowClickThrough) { $cmdParams.Add('AllowClickThrough', $AllowClickThrough) }
        if ($null -ne $ScanUrls) { $cmdParams.Add('ScanUrls', $ScanUrls) }
        if ($null -ne $EnableForInternalSenders) { $cmdParams.Add('EnableForInternalSenders', $EnableForInternalSenders) }
        if ($null -ne $DeliverMessageAfterScan) { $cmdParams.Add('DeliverMessageAfterScan', $DeliverMessageAfterScan) }
        if ($null -ne $DisableUrlRewrite) { $cmdParams.Add('DisableUrlRewrite', $DisableUrlRewrite) }
        if ($null -ne $DoNotRewriteUrls -and $DoNotRewriteUrls.Count -gt 0) { $cmdParams.Add('DoNotRewriteUrls', $DoNotRewriteUrls) }
        if ($null -ne $AdminDisplayName) { $cmdParams.Add('AdminDisplayName', $AdminDisplayName) }
        if ($null -ne $CustomNotificationText) { $cmdParams.Add('CustomNotificationText', $CustomNotificationText) }
        if ($null -ne $EnableOrganizationBranding) { $cmdParams.Add('EnableOrganizationBranding', $EnableOrganizationBranding) }

        $ExoRequestParam = @{
            tenantid         = $TenantFilter
            cmdlet           = 'Set-SafeLinksPolicy'
            cmdParams        = $cmdParams
            useSystemMailbox = $true
        }

        $null = New-ExoRequest @ExoRequestParam
        $Result = "Successfully updated SafeLinks policy '$PolicyName'"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed updating SafeLinks policy '$PolicyName'. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })
}
