using namespace System.Net

Function Invoke-ExecBrandingSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $StatusCode = [HttpStatusCode]::OK
    @{}

    try {
        $Table = Get-CIPPTable -TableName Config
        $Filter = "PartitionKey eq 'BrandingSettings' and RowKey eq 'BrandingSettings'"
        $BrandingConfig = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        if (-not $BrandingConfig) {
            $BrandingConfig = @{
                PartitionKey = 'BrandingSettings'
                RowKey       = 'BrandingSettings'
                colour       = '#F77F00'
                logo         = $null
            }
        }

        $Action = if ($Request.Body.Action) { $Request.Body.Action } else { $Request.Query.Action }

        $Results = switch ($Action) {
            'Get' {
                @{
                    colour = $BrandingConfig.colour
                    logo   = $BrandingConfig.logo
                }
            }
            'Set' {
                $Updated = $false

                if ($Request.Body.colour) {
                    $Colour = $Request.Body.colour
                    if ($Colour -match '^#[0-9A-Fa-f]{6}$') {
                        $BrandingConfig.colour = $Colour
                        $Updated = $true
                    } else {
                        $StatusCode = [HttpStatusCode]::BadRequest
                        'Error: Invalid color format. Please use hex format (e.g., #F77F00)'
                    }
                }

                if ($Request.Body.logo) {
                    $Logo = $Request.Body.logo
                    if ($Logo -match '^data:image\/') {
                        $Base64Data = $Logo -replace '^data:image\/[^;]+;base64,', ''
                        try {
                            $ImageBytes = [Convert]::FromBase64String($Base64Data)
                            if ($ImageBytes.Length -le 2097152) {
                                Write-Host 'updating logo'
                                $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'logo' -Value $Logo -Force
                                $Updated = $true
                            } else {
                                $StatusCode = [HttpStatusCode]::BadRequest
                                'Error: Image size must be less than 2MB'
                            }
                        } catch {
                            $StatusCode = [HttpStatusCode]::BadRequest
                            'Error: Invalid base64 image data: ' + $_.Exception.Message
                        }
                    } elseif ($Logo -eq $null -or $Logo -eq '') {
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'logo' -Value $null -Force
                        $Updated = $true
                    }
                }

                if ($Updated) {
                    $BrandingConfig.PartitionKey = 'BrandingSettings'
                    $BrandingConfig.RowKey = 'BrandingSettings'

                    Add-CIPPAzDataTableEntity @Table -Entity $BrandingConfig -Force | Out-Null
                    Write-LogMessage -API $APIName -tenant 'Global' -headers $Request.Headers -message 'Updated branding settings' -Sev 'Info'
                    'Successfully updated branding settings'
                } else {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    'Error: No valid branding data provided'
                }
            }
            'Reset' {
                $DefaultConfig = @{
                    PartitionKey = 'BrandingSettings'
                    RowKey       = 'BrandingSettings'
                    colour       = '#F77F00'
                    logo         = $null
                }

                Add-CIPPAzDataTableEntity @Table -Entity $DefaultConfig -Force | Out-Null
                Write-LogMessage -API $APIName -tenant 'Global' -headers $Request.Headers -message 'Reset branding settings to defaults' -Sev 'Info'
                'Successfully reset branding settings to defaults'
            }
            default {
                $StatusCode = [HttpStatusCode]::BadRequest
                'Error: Invalid action specified'
            }
        }
    } catch {
        Write-LogMessage -API $APIName -tenant 'Global' -headers $Request.Headers -message "Branding Settings API failed: $($_.Exception.Message)" -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
        "Failed to process branding settings: $($_.Exception.Message)"
    }

    $body = [pscustomobject]@{'Results' = $Results }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })
}
