using namespace System.Net

Function Invoke-ListUserConditionalAccessPolicies {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'




    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $UserID = $Request.Query.UserID

    try {
        $IncludeApplications = '67ad5377-2d78-4ac2-a867-6300cda00e85'
        $CAContext = @{
            '@odata.type'         = '#microsoft.graph.whatIfApplicationContext'
            'includeApplications' = @($IncludeApplications)
        }
        $ConditionalAccessWhatIfDefinition = @{
            'conditionalAccessWhatIfSubject'    = @{
                '@odata.type' = '#microsoft.graph.userSubject'
                'userId'      = "$userId"
            }
            'conditionalAccessContext'          = $CAContext
            'conditionalAccessWhatIfConditions' = @{}
        }
        $JSONBody = $ConditionalAccessWhatIfDefinition | ConvertTo-Json -Depth 10

        $GraphRequest = (New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/evaluate' -tenantid $tenantFilter -type POST -body $JsonBody -AsApp $true).value
    } catch {
        $GraphRequest = @{}
    }

    Write-Host $GraphRequest

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}
