using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$Device = $request.query.ID
try {

    $object = [pscustomobject]@{
        startDateTime	= (Get-Date).ToString("O")
        endDateTime   = (Get-Date).AddYears('1').ToString("O")
        frequency     = 'weeklyOnce'
        targeting     = @{
            targetingType = 'aadGroup'
            includeIds    = @($Device)
        }
        content       = @{
            "guidedContentId" = "ce57aa57-7ed5-4ea1-87a8-f1764b03de8f"
            placementDetails  = @(@{
                    placement = 'card0'
                    variants  = @(@{
                            variantId      = "ed0d0fa2-df72-42f4-9866-66cf3de1fafb"
                            localizedTexts = @(@{
                                    locale = "invariant"
                                    text   = @{
                                        "message"    = "My Message Value"
                                        "clickUrl"   = "https://example.com/clickUrl/"
                                        "title"      = "This message"
                                        "buttonText" = "PlzClick"
                                    }
                                })
                        })
                }
                @{
                    placement = 'card1'
                    variants  = @(@{
                            variantId      = "ed0d0fa2-df72-42f4-9866-66cf3de1fafb"
                            localizedTexts = @(@{
                                    locale = "invariant"
                                    text   = @{
                                        "message"    = "My Message Value"
                                        "clickUrl"   = "https://example.com/clickUrl/"
                                        "title"      = "This message"
                                        "buttonText" = "PlzClick"
                                    }
                                })
                        })
                })
            logoInfo          = @{
                contentType = "png"
                logoCdnUrl  = 'https://hulpnu.nl/tools/Red.jpg'
            }
        }
    }
    $tmpbody = ConvertTo-Json -Depth 15 -Compress -InputObject $object
    Write-Host $tmpbody

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
