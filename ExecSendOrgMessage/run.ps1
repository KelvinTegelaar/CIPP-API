using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
try {

    $tmpbody = ConvertTo-Json -Depth 10 -InputObject @{
        scenario      = "lifecycle"
        surface       = "actionCenter"
        startDateTime	= (Get-Date).ToString("O")
        endDateTime   = (Get-Date).AddDays('10').ToString("O")
        frequency     = 'weeklyOnce'
        theme         = "welcomeToWindows"
        targeting     = @{
            targetingType = 'aadGroup'
            includeIds    = @('71a0e6ca-2019-497d-a922-a3d528566b40')
        }
        content       = @{
            placementDetails = @(@{
                    placement = 'default'
                    variants  = @(@{
                            variantId      = (New-Guid).Guid
                            name           = (New-Guid).Guid
                            localizedTexts = @(@{
                                    text = @{
                                        title      = 'Title value'
                                        message    = 'Message value'
                                        clickUrl   = 'https://example.com/clickUrl/'
                                        buttonText = 'Button Text value'
                                    }
                                })
                        })
                })
            logoInfo         = @{
                logoCdnUrl = 'https://example.com/logoCdnUrl/'
            }
        }
    }
    $GraphRequest = New-GraphPOSTRequest -noauthcheck $true -type "POST" -uri "https://graph.microsoft.com/beta/deviceManagement/organizationalMessageDetails" -tenantid $tenantfilter -body $tmpbody

    $StatusCode = [HttpStatusCode]::OK
}
catch {
    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
    $StatusCode = [HttpStatusCode]::Forbidden
    $GraphRequest = $ErrorMessage
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    })
