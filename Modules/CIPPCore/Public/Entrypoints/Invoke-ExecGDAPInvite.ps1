using namespace System.Net
Function Invoke-ExecGDAPInvite {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $RoleMappings = $Request.body.gdapRoles
    $Results = [System.Collections.Generic.List[string]]::new()

    if ($RoleMappings.roleDefinitionId -contains '62e90394-69f5-4237-9190-012177145e10') {
        $AutoExtendDuration = 'PT0S'
    } else {
        $AutoExtendDuration = 'P180D'
    }

    $Table = Get-CIPPTable -TableName 'GDAPInvites'
    try {
        $JSONBody = @{
            'displayName'        = "$((New-Guid).GUID)"
            'accessDetails'      = @{
                'unifiedRoles' = @($RoleMappings | Select-Object roleDefinitionId)
            }
            'autoExtendDuration' = $AutoExtendDuration
            'duration'           = 'P730D'
        } | ConvertTo-Json -Depth 5 -Compress

        $NewRelationship = New-GraphPostRequest -NoAuthCheck $True -uri 'https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships' -type POST -body $JSONBody -verbose -tenantid $env:TenantID
        Start-Sleep -Milliseconds 100
        $Count = 0
        do {
            $CheckActive = New-GraphGetRequest -NoAuthCheck $True -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$($NewRelationship.id)" -tenantid $env:TenantID
            Start-Sleep -Milliseconds 200
            $Count++
        } until ($CheckActive.status -eq 'created' -or $Count -gt 5)

        if ($CheckActive.status -eq 'created') {
            # Lock for approval
            $JSONBody = @{
                'action' = 'lockForApproval'
            } | ConvertTo-Json
            $NewRelationshipRequest = New-GraphPostRequest -NoAuthCheck $True -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$($NewRelationship.id)/requests" -type POST -body $JSONBody -verbose -tenantid $env:TenantID

            if ($NewRelationshipRequest.action -eq 'lockForApproval') {
                $InviteUrl = "https://admin.microsoft.com/AdminPortal/Home#/partners/invitation/granularAdminRelationships/$($NewRelationship.id)"

                $InviteEntity = [PSCustomObject]@{
                    'PartitionKey' = 'invite'
                    'RowKey'       = $NewRelationship.id
                    'InviteUrl'    = $InviteUrl
                    'RoleMappings' = [string](@($RoleMappings) | ConvertTo-Json -Depth 10 -Compress)
                }
                Add-CIPPAzDataTableEntity @Table -Entity $InviteEntity

                $Results.add('GDAP relationship invite created. Copy the URL below and log in as a Global Admin for the new tenant to approve the invite.')
            } else {
                $Results.add('Error creating GDAP relationship request')
            }
        }
    } catch {
        $Results.add('Error creating GDAP relationship')
        Write-Host "GDAP ERROR: $($_.Exception.Message)"
    }

    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Created GDAP Invite - $InviteUrl" -Sev 'Info'

    $body = @{
        Results = @($Results)
        Invite  = $InviteEntity
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })
}
