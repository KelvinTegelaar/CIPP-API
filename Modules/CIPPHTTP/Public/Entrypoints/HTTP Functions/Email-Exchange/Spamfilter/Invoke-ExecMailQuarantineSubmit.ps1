function Invoke-ExecMailQuarantineSubmit {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
    .DESCRIPTION
        Submits a quarantined email message to Microsoft for review (threat submission) via the Graph API.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    try {
        $TenantFilter = $Request.Body.tenantFilter | Select-Object -First 1
        $Identity = $Request.Body.Identity
        $Category = $Request.Body.category.value ?? $Request.Body.category
        $Recipient = @($Request.Body.RecipientAddress) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1

        if ([string]::IsNullOrEmpty($Identity)) { throw 'No quarantine message Identity provided' }
        if ($Category -notin @('notJunk', 'spam', 'phishing', 'malware')) { throw "Invalid submission category '$Category'" }
        if ([string]::IsNullOrEmpty($Recipient)) { throw 'No recipient address provided' }

        # Export the quarantined message and submit its content to Microsoft for analysis
        $Export = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Export-QuarantineMessage' -cmdParams @{ 'Identity' = $Identity }
        if ([string]::IsNullOrEmpty($Export.Eml)) { throw 'Could not export the quarantined message' }

        $GraphBody = ConvertTo-Json -Depth 5 -InputObject @{
            '@odata.type'         = '#microsoft.graph.security.emailContentThreatSubmission'
            category              = $Category
            recipientEmailAddress = $Recipient
            fileContent           = $Export.Eml
        }
        $null = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/security/threatSubmission/emailThreats' -tenantid $TenantFilter -AsApp $true -body $GraphBody

        $Message = "Successfully submitted quarantined message $Identity to Microsoft for review as '$Category'"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
        $Results = [pscustomobject]@{'Results' = $Message }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Quarantine message submission failed: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Results = [pscustomobject]@{'Results' = "Failed to submit message for review. $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
