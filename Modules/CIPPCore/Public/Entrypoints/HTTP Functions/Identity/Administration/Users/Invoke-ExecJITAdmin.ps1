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

    $APIName = 'ExecJITAdmin'
    Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    if ($Request.Query.Action -eq 'List') {
        $Schema = Get-CIPPSchemaExtensions | Where-Object { $_.id -match '_cippUser' }
        #Write-Information "Schema: $($Schema)"
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
        $BulkRequests = $Users | ForEach-Object { @(
                @{
                    id     = $_.id
                    method = 'GET'
                    url    = "users/$($_.id)/memberOf/microsoft.graph.directoryRole/?`$select=id,displayName"
                }
            )
        }
        $RoleResults = New-GraphBulkRequest -tenantid $Request.Query.TenantFilter -Requests @($BulkRequests)
        #Write-Information ($RoleResults | ConvertTo-Json -Depth 10 )
        $Results = $Users | ForEach-Object {
            $MemberOf = ($RoleResults | Where-Object -Property id -EQ $_.id).body.value | Select-Object displayName, id
            [PSCustomObject]@{
                id                 = $_.id
                displayName        = $_.displayName
                userPrincipalName  = $_.userPrincipalName
                jitAdminEnabled    = $_.($Schema.id).jitAdminEnabled
                jitAdminExpiration = $_.($Schema.id).jitAdminExpiration
                memberOf           = $MemberOf
            }
        }

        #Write-Information ($Results | ConvertTo-Json -Depth 10)
        $Body = @{
            Results  = @($Results)
            Metadata = @{
                Parameters = $Query.Parameters
            }
        }
    } else {
        Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APINAME -message "Executing JIT Admin for $($Request.Body.UserPrincipalName)" -Sev 'Info'
        if ($Request.Body.UserId -match '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$') {
            $Username = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($Request.Body.UserId)" -tenantid $Request.Body.TenantFilter).userPrincipalName
        }

        $Start = ([System.DateTimeOffset]::FromUnixTimeSeconds($Request.Body.StartDate)).DateTime.ToLocalTime()
        $Expiration = ([System.DateTimeOffset]::FromUnixTimeSeconds($Request.Body.EndDate)).DateTime.ToLocalTime()
        $Results = [System.Collections.Generic.List[string]]::new()

        if ($Request.Body.useraction -eq 'create') {
            Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APINAME -message "Creating JIT Admin user $($Request.Body.UserPrincipalName)" -Sev 'Info'
            Write-Information "Creating JIT Admin user $($Request.Body.UserPrincipalName)"
            $JITAdmin = @{
                User         = @{
                    'FirstName'         = $Request.Body.FirstName
                    'LastName'          = $Request.Body.LastName
                    'UserPrincipalName' = $Request.Body.UserPrincipalName
                }
                Expiration   = $Expiration
                Action       = 'Create'
                TenantFilter = $Request.Body.TenantFilter
            }
            $CreateResult = Set-CIPPUserJITAdmin @JITAdmin
            $Username = $CreateResult.userPrincipalName
            $Results.Add("Created User: $($CreateResult.userPrincipalName)")
            $Results.Add("Password: $($CreateResult.password)")
            Start-Sleep -Seconds 1
        }
        $Parameters = @{
            TenantFilter = $Request.Body.TenantFilter
            User         = @{
                'UserPrincipalName' = $Username
            }
            Roles        = $Request.Body.AdminRoles
            Action       = 'AddRoles'
            Expiration   = $Expiration
        }
        if ($Start -gt (Get-Date)) {
            $TaskBody = @{
                TenantFilter  = $Request.Body.TenantFilter
                Name          = "JIT Admin (enable): $Username"
                Command       = @{
                    value = 'Set-CIPPUserJITAdmin'
                    label = 'Set-CIPPUserJITAdmin'
                }
                Parameters    = $Parameters
                ScheduledTime = $Request.Body.StartDate
                PostExecution = @{
                    Webhook = [bool]$Request.Body.PostExecution.Webhook
                    Email   = [bool]$Request.Body.PostExecution.Email
                    PSA     = [bool]$Request.Body.PostExecution.PSA
                }
            }
            Add-CIPPScheduledTask -Task $TaskBody -hidden $false
            Set-CIPPUserJITAdminProperties -TenantFilter $Request.Body.TenantFilter -UserId $Request.Body.UserId -Expiration $Expiration
            $Results.Add("Scheduling JIT Admin enable task for $Username")
        } else {
            $Results.Add("Executing JIT Admin enable task for $Username")
            Set-CIPPUserJITAdmin @Parameters
        }

        $DisableTaskBody = @{
            TenantFilter  = $Request.Body.TenantFilter
            Name          = "JIT Admin (disable): $Username"
            Command       = @{
                value = 'Set-CIPPUserJITAdmin'
                label = 'Set-CIPPUserJITAdmin'
            }
            Parameters    = @{
                TenantFilter = $Request.Body.TenantFilter
                User         = @{
                    'UserPrincipalName' = $Username
                }
                Roles        = $Request.Body.AdminRoles
                Action       = $Request.Body.ExpireAction
            }
            PostExecution = @{
                Webhook = [bool]$Request.Body.PostExecution.Webhook
                Email   = [bool]$Request.Body.PostExecution.Email
                PSA     = [bool]$Request.Body.PostExecution.PSA
            }
            ScheduledTime = $Request.Body.EndDate
        }
        Add-CIPPScheduledTask -Task $DisableTaskBody -hidden $false
        $Results.Add("Scheduling JIT Admin disable task for $Username")
        $Body = @{
            Results = @($Results)
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
