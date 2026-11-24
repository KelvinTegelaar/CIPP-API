Function Invoke-AddCATemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $Name = $Request.Body.name ?? $Request.Body.displayName
    # Replace the template with this policy's name instead of adding another one.
    $ReplaceExisting = $Request.Body.ReplaceExisting -eq $true
    # Keep the %variables% added to the stored template where the policy still has those settings.
    $KeepVariables = $Request.Body.KeepVariables -eq $true
    # Options, not policy properties, so they stay out of the stored template
    $null = $Request.Body.PSObject.Properties.Remove('ReplaceExisting')
    $null = $Request.Body.PSObject.Properties.Remove('KeepVariables')
    try {
        $GUID = (New-Guid).GUID
        $JSON = New-CIPPCATemplate -TenantFilter $TenantFilter -JSON $Request.Body
        $Table = Get-CippTable -tablename 'templates'
        $Replaced = $null
        $Dropped = [System.Collections.Generic.HashSet[string]]::new()
        if ($ReplaceExisting) {
            $Captured = $JSON | ConvertFrom-Json -Depth 100
            $SameName = @(foreach ($Row in (Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CATemplate'")) {
                    $Data = $(try { $Row.JSON | ConvertFrom-Json -Depth 100 } catch { $null })
                    if ($Data.displayName -eq $Captured.displayName) { @{ Row = $Row; Data = $Data } }
                })
            if ($SameName.Count -gt 1) {
                throw [System.ArgumentException]::new("$($SameName.Count) templates are named '$($Captured.displayName)'. Rename all but one of them, then capture the policy again.")
            }
            foreach ($Candidate in $SameName) { $Replaced = $Candidate }
            if ($Replaced) {
                $GUID = $Replaced.Row.RowKey
                if ($KeepVariables) {
                    $JSON = ConvertTo-Json -InputObject (Merge-CIPPTemplateVariable -Existing $Replaced.Data -Captured $Captured -Dropped $Dropped) -Depth 100 -Compress
                }
            }
        }
        $Entity = @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'CATemplate'
            GUID         = "$GUID"
        }
        if ($Replaced.Row.Package) { $Entity.Package = $Replaced.Row.Package }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
        $Result = if ($Replaced) { "Updated CA Template $($Name) with GUID $GUID" } else { "Created CA Template $($Name) with GUID $GUID" }
        $ProfileRef = ($JSON | ConvertFrom-Json).sessionControls.globalSecureAccessFilteringProfile.profileId
        $Warnings = @(
            if ($Dropped.Count -gt 0) { "These variables were on settings the policy no longer has, so they were not kept: $(@($Dropped) -join ', ')" }
            if ($ProfileRef -is [string] -and $ProfileRef) { "This policy applies the Global Secure Access security profile '$ProfileRef'. The CA template refers to it by name, so each tenant it is deployed to needs a security profile with that name. To deploy the profile with the policy, save it with Save as Template on the Global Secure Access Security Profiles page and link that template in this CA template." }
        )
        if ($Warnings.Count -gt 0) {
            $Result = @(
                [pscustomobject]@{ state = 'success'; resultText = $Result }
                foreach ($Warning in $Warnings) { [pscustomobject]@{ state = 'warning'; resultText = $Warning } }
            )
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "$(if ($Replaced) { 'Updated' } else { 'Created' }) CA Template $($Name) with GUID $GUID" -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create CA Template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Failed to create CA Template: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }


    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })

}
