function Invoke-ExecCAExclusion {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers

    try {
        #If UserId is a guid, get the user's UPN
        $TenantFilter = $Request.Body.tenantFilter
        $UserID = $Request.Body.UserID
        $Username = $Request.Body.Username
        $Users = $Request.Body.Users
        $EndDate = $Request.Body.EndDate
        $PolicyId = $Request.Body.PolicyId
        $ExclusionType = $Request.Body.ExclusionType

        if ($Users) {
            $UserID = $Users.value
            $Username = $Users.addedFields.userPrincipalName -join ', '
        } else {
            if ($UserID -match '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$' -and -not $Username) {
                $Username = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserID)" -tenantid $TenantFilter).userPrincipalName
            }
        }

        $Policy = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($PolicyId)?`$select=id,displayName" -tenantid $TenantFilter -asApp $true

        if (-not $Policy) {
            throw "Policy with ID $PolicyId not found in tenant $TenantFilter."
        }

        $PolicyName = $Policy.displayName
        if ($Request.Body.vacation -eq 'true') {
            $StartDate = $Request.Body.StartDate
            $EndDate = $Request.Body.EndDate

            $Parameters = [PSCustomObject]@{
                ExclusionType = 'Add'
                PolicyId      = $PolicyId
            }

            if ($Users) {
                $Parameters | Add-Member -NotePropertyName Users -NotePropertyValue $Users
            } else {
                $Parameters | Add-Member -NotePropertyName UserID -NotePropertyValue $UserID
            }

            $TaskBody = [pscustomobject]@{
                TenantFilter  = $TenantFilter
                Name          = "Add CA Exclusion Vacation Mode: $PolicyName"
                Command       = @{
                    value = 'Set-CIPPCAExclusion'
                    label = 'Set-CIPPCAExclusion'
                }
                Parameters    = [pscustomobject]$Parameters
                ScheduledTime = $StartDate
            }

            Write-Information ($TaskBody | ConvertTo-Json -Depth 10)

            Add-CIPPScheduledTask -Task $TaskBody -hidden $false
            #Removal of the exclusion
            $TaskBody.Parameters.ExclusionType = 'Remove'
            $TaskBody.Name = "Remove CA Exclusion Vacation Mode: $PolicyName"
            $TaskBody.ScheduledTime = $EndDate
            Add-CIPPScheduledTask -Task $TaskBody -hidden $false
            $body = @{ Results = "Successfully added vacation mode schedule for $Username." }
        } else {
            $Parameters = @{
                ExclusionType = $ExclusionType
                PolicyId      = $PolicyId
            }
            if ($Users) {
                $Parameters.Users = $Users
            } else {
                $Parameters.UserID = $UserID
            }

            Set-CIPPCAExclusion -TenantFilter $TenantFilter -Headers $Headers @Parameters
        }
    } catch {
        Write-Warning "Failed to perform exclusion for $Username : $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
        $body = @{ Results = "Failed to perform exclusion for $Username : $($_.Exception.Message)" }
        Write-LogMessage -headers $Headers -API 'Invoke-ExecCAExclusion' -message "Failed to perform exclusion for $Username : $_" -Sev 'Error' -tenant $TenantFilter -LogData (Get-CippException -Exception $_)
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
