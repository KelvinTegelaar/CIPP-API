using namespace System.Net

Function Invoke-ExecCAExclusion {
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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    #If UserId is a guid, get the user's UPN
    $TenantFilter = $Request.Body.tenantFilter
    $UserId = $Request.Body.UserID
    $EndDate = $Request.Body.EndDate
    $PolicyId = $Request.Body.PolicyId
    $ExclusionType = $Request.Body.ExclusionType


    if ($UserId -match '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$') {
        $Username = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserId)" -tenantid $TenantFilter).userPrincipalName
    }
    if ($Request.Body.vacation -eq 'true') {
        $StartDate = $Request.Body.StartDate
        $EndDate = $Request.Body.EndDate
        $TaskBody = [pscustomobject]@{
            TenantFilter  = $TenantFilter
            Name          = "Add CA Exclusion Vacation Mode: $Username - $($TenantFilter)"
            Command       = @{
                value = 'Set-CIPPCAExclusion'
                label = 'Set-CIPPCAExclusion'
            }
            Parameters    = [pscustomobject]@{
                ExclusionType = 'Add'
                UserID        = $UserID
                PolicyId      = $PolicyId
                UserName      = $Username
            }
            ScheduledTime = $StartDate
        }
        Add-CIPPScheduledTask -Task $TaskBody -hidden $false
        #Removal of the exclusion
        $TaskBody.Parameters.ExclusionType = 'Remove'
        $TaskBody.Name = "Remove CA Exclusion Vacation Mode: $Username - $($TenantFilter)"
        $TaskBody.ScheduledTime = $EndDate
        Add-CIPPScheduledTask -Task $TaskBody -hidden $false
        $body = @{ Results = "Successfully added vacation mode schedule for $Username." }
    } else {
        Set-CIPPCAExclusion -TenantFilter $TenantFilter -ExclusionType $ExclusionType -UserID $UserID -PolicyId $PolicyId -Headers $Headers -UserName $Username
    }


    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
