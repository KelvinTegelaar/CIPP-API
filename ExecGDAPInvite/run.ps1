using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

$RoleMappings = $Request.body.gdapRoles
$Results = [System.Collections.Generic.List[string]]::new()
$InviteUrls = [System.Collections.Generic.List[string]]::new()

$Table = Get-CIPPTable -TableName 'GDAPInvites'
try {
    $JSONBody = @{
        'displayName'        = "$((New-Guid).GUID)"
        'accessDetails'      = @{
            'unifiedRoles' = @($RoleMappings | Select-Object roleDefinitionId)
        }
        'autoExtendDuration' = 'P180D'
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
            $InviteUrls.Add($InviteUrl)

            $InviteEntity = [PSCustomObject]@{
                'PartitionKey' = 'invite'
                'RowKey'       = $NewRelationship.id
                'InviteUrl'    = $InviteUrl
                'RoleMappings' = [string](@($RoleMappings) | ConvertTo-Json -Depth 10)
            }
            Add-CIPPAzDataTableEntity @Table -Entity $InviteEntity

            $Results.add("Relationship created - Invite URL: $InviteUrl")
        } else {
            $Results.add('Error creating GDAP relationship request')
        }
    }
} catch {
    $Results.add('Error creating GDAP relationship')
}

Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Created GDAP Invite - $InviteUrl" -Sev 'Info'

$body = @{
    Results    = @($Results)
    InviteUrls = @($InviteUrls)
}
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })