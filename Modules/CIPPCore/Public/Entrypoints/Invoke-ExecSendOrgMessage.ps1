using namespace System.Net

Function Invoke-ExecSendOrgMessage {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $Device = $request.query.ID
    try {

        $type = switch ($request.Query.type) {
            'taskbar' {
                '844ec9d0-dd31-459c-a1e7-21fb1b39d5da'
                $placementDetails = @(@{
                        placement = 'default'
                        variants  = @(@{
                                variantId      = 'b3fce1ee-9658-4267-b174-23d4a1be148f'
                                localizedTexts = @(@{
                                        locale = 'invariant'
                                        text   = @{
                                            'clickUrl' = $Request.query.URL
                                        }
                                    })
                            })
                    })
            }
            'notification' {
                '1ff7c7e7-128c-4e18-a926-bdac4e906ea1'
                $placementDetails = @(@{
                        placement = 'default'
                        variants  = @(@{
                                variantId      = '7a1419c9-9263-4202-9225-35b326b92792'
                                localizedTexts = @(@{
                                        locale = 'invariant'
                                        text   = @{
                                            'clickUrl' = $Request.query.URL
                                        }
                                    })
                            })
                    })
            }
            'getStarted' {
                $placementDetails = @(@{
                        placement = 'card0'
                        variants  = @(@{
                                variantId      = 'ed0d0fa2-df72-42f4-9866-66cf3de1fafb'
                                localizedTexts = @(@{
                                        locale = 'invariant'
                                        text   = @{
                                            'message'    = 'My Message Value'
                                            'clickUrl'   = 'https://example.com/clickUrl/'
                                            'title'      = 'This message'
                                            'buttonText' = 'PlzClick'
                                        }
                                    })
                            })
                    }
                    @{
                        placement = 'card1'
                        variants  = @(@{
                                variantId      = 'ed0d0fa2-df72-42f4-9866-66cf3de1fafb'
                                localizedTexts = @(@{
                                        locale = 'invariant'
                                        text   = @{
                                            'message'    = 'My Message Value'
                                            'clickUrl'   = 'https://example.com/clickUrl/'
                                            'title'      = 'This message'
                                            'buttonText' = 'PlzClick'
                                        }
                                    })
                            })
                    })
            }

        }
        $freq = $request.query.freq
        $object = [pscustomobject]@{
            startDateTime	= (Get-Date).ToString('O')
            endDateTime   = (Get-Date).AddYears('1').ToString('O')
            frequency     = $freq
            targeting     = @{
                targetingType = 'aadGroup'
                includeIds    = @($Device)
            }
            content       = @{
                'guidedContentId' = "$Type"
                placementDetails  = $placementDetails
                logoInfo          = @{
                    contentType = 'png'
                    logoCdnUrl  = 'https://hulpnu.nl/tools/Red.jpg'
                }
            }
        }
        $tmpbody = ConvertTo-Json -Depth 15 -Compress -InputObject $object
        Write-Host $tmpbody

        $GraphRequest = New-GraphPOSTRequest -noauthcheck $true -type 'POST' -uri 'https://graph.microsoft.com/beta/deviceManagement/organizationalMessageDetails' -tenantid $tenantfilter -body $tmpbody
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
