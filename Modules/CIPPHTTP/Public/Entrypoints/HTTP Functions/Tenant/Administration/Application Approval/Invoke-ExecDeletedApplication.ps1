function Invoke-ExecDeletedApplication {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.ReadWrite
    .DESCRIPTION
        Restores (Action Restore) or permanently deletes (Action Delete) a deleted app registration or enterprise app
        (service principal). Any other kind of deleted object, such as a user or group, is refused: those are managed
        from Deleted Items with directory permissions. A restore says when the matching app registration or
        enterprise app is still deleted, since restoring one does not restore the other.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $Id = "$($Request.Body.ID.value ?? $Request.Body.ID ?? $Request.Query.ID)".Trim()
    $Action = "$($Request.Body.Action.value ?? $Request.Body.Action ?? $Request.Query.Action)"

    if ($Action -notin @('Restore', 'Delete')) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = @(@{ resultText = 'Action must be Restore or Delete'; state = 'error' }) } })
    }
    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants' -or $Id -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = @(@{ resultText = 'A single tenant and a valid deleted object ID are required'; state = 'error' }) } })
    }

    $Kinds = @{
        '#microsoft.graph.application'      = @{ Label = 'app registration'; Other = 'servicePrincipal'; OtherLabel = 'enterprise app' }
        '#microsoft.graph.servicePrincipal' = @{ Label = 'enterprise app'; Other = 'application'; OtherLabel = 'app registration' }
    }
    $Name = $Id
    try {
        $Object = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/directory/deletedItems/$Id" -tenantid $TenantFilter
        $Kind = $Kinds[[string]$Object.'@odata.type']
        if (-not $Kind) {
            throw [System.ArgumentException]::new("$Id is not a deleted app registration or enterprise app: manage it from Identity > Deleted Items")
        }
        $Name = "the $($Kind.Label) '$($Object.displayName)'"

        if ($Action -eq 'Restore') {
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/directory/deletedItems/$Id/restore" -tenantid $TenantFilter -type POST -body '{}'
            $Message = "Restored $Name"
            # The app registration and its enterprise app are deleted and restored separately.
            try {
                $OtherDeleted = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/directory/deletedItems/microsoft.graph.$($Kind.Other)?`$select=id,appId&`$top=999" -tenantid $TenantFilter |
                        Where-Object { $_.appId -and $_.appId -eq $Object.appId })
                if ($OtherDeleted.Count -gt 0) {
                    $Message += ". Its $($Kind.OtherLabel) is still deleted: restore it too from Deleted Apps for the app to work in this tenant again"
                }
            } catch {
                Write-Information "Could not check whether the $($Kind.OtherLabel) of $Id is deleted: $($_.Exception.Message)"
            }
        } else {
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/directory/deletedItems/$Id" -tenantid $TenantFilter -type DELETE -body '{}'
            $Message = "Permanently deleted $Name. It can no longer be restored"
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
        $Results = @(@{ resultText = $Message; state = 'success' })
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to $(if ($Action -eq 'Restore') { 'restore' } else { 'permanently delete' }) $($Name): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
        $Results = @(@{ resultText = $Message; state = 'error' })
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Results }
        })
}
