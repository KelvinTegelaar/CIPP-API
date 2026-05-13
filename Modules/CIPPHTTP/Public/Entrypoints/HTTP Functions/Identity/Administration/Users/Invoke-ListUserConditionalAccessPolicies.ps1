Function Invoke-ListUserConditionalAccessPolicies {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # XXX - Unused endpoint?

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
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
                'userId'      = "$UserID"
            }
            'conditionalAccessContext'          = $CAContext
            'conditionalAccessWhatIfConditions' = @{}
        }
        $JSONBody = ConvertTo-Json -Depth 10 -InputObject $ConditionalAccessWhatIfDefinition -Compress

        $GraphRequest = (New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/evaluate' -tenantid $TenantFilter -type POST -body $JsonBody -AsApp $true).value
    } catch {
        $GraphRequest = @{}
    }

    Write-Host $GraphRequest

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}
