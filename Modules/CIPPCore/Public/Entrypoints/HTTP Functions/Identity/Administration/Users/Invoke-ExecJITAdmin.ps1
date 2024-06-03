using namespace System.Net

Function Invoke-ExecJITAdmin {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    Write-Information ($Request.Body | ConvertTo-Json -Depth 10)
    if ($Request.Query.Action -eq 'List') {
        $Schema = Get-CIPPSchemaExtensions | Where-Object { $_.id -match '_cippUser' }
        Write-Information "Schema: $($Schema)"
        $Query = @{
            TenantFilter = $Request.Query.TenantFilter
            Endpoint     = 'users'
            Parameters   = @{
                '$count'  = 'true'
                '$select' = "id,displayName,userPrincipalName,$($Schema.id)"
                '$filter' = "$($Schema.id)/jitAdminEnabled eq true or $($Schema.id)/jitAdminEnabled eq false"
            }
        }
        $Users = Get-GraphRequestList @Query | Where-Object { $_.id }
        $Results = $Users | ForEach-Object {
            $MemberOf = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_.id)/memberOf/microsoft.graph.directoryRole/?`$select=id,displayName" -tenantid $Request.Query.TenantFilter -ComplexFilter
            [PSCustomObject]@{
                id                 = $_.id
                displayName        = $_.displayName
                userPrincipalName  = $_.userPrincipalName
                jitAdminEnabled    = $_.($Schema.id).jitAdminEnabled
                jitAdminExpiration = $_.($Schema.id).jitAdminExpiration
                memberOf           = $MemberOf
            }
        }


        Write-Information ($Results | ConvertTo-Json -Depth 10)
        $Body = @{
            Results  = @($Results)
            Metadata = @{
                Parameters = $Query.Parameters
            }
        }
    } else {
        #If UserId is a guid, get the user's UPN
        if ($Request.body.UserId -match '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$') {
            $Username = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($Request.body.UserId)" -tenantid $Request.body.TenantFilter).userPrincipalName
        }
    }

    <#if ($Request.body.vacation -eq 'true') {
        $StartDate = $Request.body.StartDate
        $TaskBody = @{
            TenantFilter  = $Request.body.TenantFilter
            Name          = "Set JIT Admin: $Username - $($Request.body.TenantFilter)"
            Command       = @{
                value = 'Set-CIPPJITAdmin'
                label = 'Set-CIPPJITAdmin'
            }
            Parameters    = @{
                UserType = 'Add'
                UserID        = $Request.body.UserID
                PolicyId      = $Request.body.PolicyId
                UserName      = $Username
            }
            ScheduledTime = $StartDate
        }
        Add-CIPPScheduledTask -Task $TaskBody -hidden $false
        #Removal of the exclusion
        $TaskBody.Parameters.ExclusionType = 'Remove'
        $TaskBody.Name = "Remove CA Exclusion Vacation Mode: $username - $($Request.body.TenantFilter)"
        $TaskBody.ScheduledTime = $Request.body.EndDate
        Add-CIPPScheduledTask -Task $TaskBody -hidden $false
        $body = @{ Results = "Successfully added vacation mode schedule for $Username." }
    } else {
        Set-CIPPCAExclusion -TenantFilter $Request.body.TenantFilter -ExclusionType $Request.body.ExclusionType -UserID $Request.body.UserID -PolicyId $Request.body.PolicyId -executingUser $request.headers.'x-ms-client-principal' -UserName $Username
    }#>

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
