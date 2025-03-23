using namespace System.Net
Function Invoke-ExecGDAPInvite {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Relationship.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = 'ExecGDAPInvite'
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $RoleMappings = $Request.Body.roleMappings

    if ($RoleMappings.roleDefinitionId -contains '62e90394-69f5-4237-9190-012177145e10') {
        $AutoExtendDuration = 'PT0S'
    } else {
        $AutoExtendDuration = 'P180D'
    }

    $Table = Get-CIPPTable -TableName 'GDAPInvites'
    try {
        $Step = 'Creating GDAP relationship'
        $JSONBody = @{
            'displayName'        = "CIPP_$((New-Guid).GUID)"
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
            $Step = 'Locking GDAP relationship for approval'

            $AddedHeaders = @{
                'If-Match' = $NewRelationship.'@odata.etag'
            }

            $NewRelationshipRequest = New-GraphPostRequest -NoAuthCheck $True -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$($NewRelationship.id)/requests" -type POST -body $JSONBody -verbose -tenantid $env:TenantID -AddedHeaders $AddedHeaders

            if ($NewRelationshipRequest.action -eq 'lockForApproval') {
                $InviteUrl = "https://admin.microsoft.com/AdminPortal/Home#/partners/invitation/granularAdminRelationships/$($NewRelationship.id)"
                try {
                    $Uri = ([System.Uri]$TriggerMetadata.Headers.Referer)
                    $OnboardingUrl = $Uri.AbsoluteUri.Replace($Uri.PathAndQuery, "/tenant/gdap-management/onboarding/start?id=$($NewRelationship.id)")
                } catch {
                    $OnboardingUrl = $null
                }

                $InviteEntity = [PSCustomObject]@{
                    'PartitionKey'  = 'invite'
                    'RowKey'        = $NewRelationship.id
                    'InviteUrl'     = $InviteUrl
                    'OnboardingUrl' = $OnboardingUrl
                    'RoleMappings'  = [string](@($RoleMappings) | ConvertTo-Json -Depth 10 -Compress)
                }
                Add-CIPPAzDataTableEntity @Table -Entity $InviteEntity

                $Message = 'GDAP relationship invite created. Log in as a Global Admin in the new tenant to approve the invite.'
            } else {
                $Message = 'Error creating GDAP relationship request'
            }

            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Created GDAP Invite - $InviteUrl" -Sev 'Info'
        }
    } catch {
        $Message = 'Error creating GDAP relationship, failed at step: ' + $Step
        Write-Host "GDAP ERROR: $($_.InvocationInfo.PositionMessage)"

        if ($Step -eq 'Creating GDAP relationship' -and $_.Exception.Message -match 'The user (principal) does not have the required permissions to perform the specified action on the resource.') {
            $Message = 'Error creating GDAP relationship, ensure that all users have MFA enabled and enforced without exception. Please see the Microsoft Partner Security Requirements documentation for more information. https://learn.microsoft.com/en-us/partner-center/security/partner-security-requirements'
        } else {
            $Message = "$($Message): $($_.Exception.Message)"
        }

        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $env:TenantID -message $Message -Sev 'Error' -LogData (Get-CippException -Exception $_)
    }

    $body = @{
        Message = $Message
        Invite  = $InviteEntity
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })
}
