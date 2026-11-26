function Invoke-ExecCyberInsuranceAttestation {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Reports.ReadWrite
    .SYNOPSIS
        Save an MSP attestation for a cyber insurance question
    .DESCRIPTION
        Saves the MSP's attestation for one question of a tenant's Cyber Insurance Readiness report, with who entered it and when. Send an Id to attest to an existing question, or a Question to add a new attestation question for the tenant. Send an Answer of Yes or No to set the MSP's answer to a question. Saving an empty attestation removes it, and removes a question the MSP added.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Body.tenantFilter
    # The question to attest to: its number on the application (1 to 25), or the id of a question the MSP added.
    $Id = [string]$Request.Body.Id
    # The text of a new attestation question. Used when no Id is sent.
    $Question = [string]$Request.Body.Question
    # The attestation text, as HTML from the editor.
    $Attestation = [string]$Request.Body.Attestation
    # Sets the MSP's answer to the question without changing its attestation text.
    $Answer = switch ($Request.Body.Answer) { 'Yes' { 'Yes' } 'No' { 'No' } default { '' } }

    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'An attestation is saved for a single tenant' } })
    }
    if ($Id -and $Id -notmatch '^([1-9]|1\d|2[0-5]|Custom-\d+)$') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Id must be a question number from 1 to 25 or the id of an added question' } })
    }
    if (-not $Id -and -not $Question.Trim()) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Enter the question to add' } })
    }

    try {
        $Tenant = @(Get-Tenants -TenantFilter $TenantFilter -IncludeErrors)[0]
        if (-not $Tenant.customerId) { throw [System.Management.Automation.ItemNotFoundException]::new("Tenant $TenantFilter was not found") }

        $Table = Get-CippTable -tablename 'CyberInsuranceAttestations'
        $RowKey = if ($Id) { $Id } else { "Custom-$([datetime]::UtcNow.Ticks)" }
        $Existing = if ($Id) { Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$($Tenant.customerId)' and RowKey eq '$RowKey'" }
        if ($Id -like 'Custom-*') {
            if (-not $Existing) { throw [System.Management.Automation.ItemNotFoundException]::new('That attestation question no longer exists') }
            $Question = [string]$Existing.Question
        }
        $Label = if ($RowKey -like 'Custom-*') { "added question '$Question'" } else { "question $RowKey" }

        if ($Answer) {
            if (-not $Id) { throw [System.ArgumentException]::new('An answer is set on an existing question') }
            Add-CIPPAzDataTableEntity @Table -Force -Entity @{
                PartitionKey = [string]$Tenant.customerId
                RowKey       = [string]$RowKey
                Question     = $Question
                Answer       = $Answer
                Attestation  = [string]$Existing.Attestation
                AttestedBy   = [string]$Request.Headers.'x-ms-client-principal-name'
                AttestedDate = (Get-Date).ToUniversalTime().ToString('o')
            }
            $Result = "Set the answer for $Label to $Answer"
        } elseif (-not ($Attestation -replace '<[^>]+>|&nbsp;|\s')) {
            if (-not $Id) { throw [System.ArgumentException]::new('Enter the attestation for the new question') }
            if ($Existing) { Remove-AzDataTableEntity @Table -Entity $Existing -Force }
            $Result = "Removed the attestation for $Label"
        } else {
            Add-CIPPAzDataTableEntity @Table -Force -Entity @{
                PartitionKey = [string]$Tenant.customerId
                RowKey       = [string]$RowKey
                Question     = $Question
                Answer       = [string]$Existing.Answer
                Attestation  = $Attestation
                AttestedBy   = [string]$Request.Headers.'x-ms-client-principal-name'
                AttestedDate = (Get-Date).ToUniversalTime().ToString('o')
            }
            $Result = "Saved the attestation for $Label"
        }
        Write-LogMessage -Headers $Request.Headers -API $Request.Params.CIPPEndpoint -tenant $TenantFilter -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to save the attestation: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Request.Headers -API $Request.Params.CIPPEndpoint -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
