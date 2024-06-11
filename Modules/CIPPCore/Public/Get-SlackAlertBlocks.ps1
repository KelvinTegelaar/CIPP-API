function Get-SlackAlertBlocks {
    [CmdletBinding()]
    Param(
        $JSONBody
    )

    $Blocks = [system.collections.generic.list[object]]::new()

    $Payload = $JSONBody | ConvertFrom-Json

    if ($Payload.API -eq 'Alerts') {
        foreach ($Entry in $Payload) {
            # Alert log alerts
            $Blocks.Add([PSCustomObject]@{
                    type = 'header'
                    text = @{
                        type  = 'plain_text'
                        text  = 'New Alert from CIPP'
                        emoji = $true
                    }
                })
            $Blocks.Add([PSCustomObject]@{
                    type   = 'section'
                    fields = @(
                        @{
                            type = 'mrkdwn'
                            text = "*Tenant:*`n" + $Entry.Tenant
                        },
                        @{
                            type = 'mrkdwn'
                            text = "*Username:*`n" + $Entry.Username
                        },
                        @{
                            type = 'mrkdwn'
                            text = "*Timestamp:*`n" + ($Entry.Timestamp | Get-Date).ToString('yyyy-MM-dd @ hh:mm:ss tt')
                        }
                    )
                })

            $Blocks.Add([PSCustomObject]@{
                    type = 'section'
                    text = @{
                        type = 'mrkdwn'
                        text = "*Message:*`n" + $Entry.Message
                    }
                })
        }
    } elseif ($Payload.TaskInfo -is [object]) {
        #Scheduler
        $Blocks.Add([PSCustomObject]@{
                type = 'header'
                text = @{
                    type  = 'plain_text'
                    text  = 'New Alert from CIPP'
                    emoji = $true
                }
            })
        $Blocks.Add([PSCustomObject]@{
                type = 'section'
                text = @{
                    type = 'mrkdwn'
                    text = "*Task Name:*`n" + $Payload.TaskInfo.Name
                }
            })
        $Blocks.Add([PSCustomObject]@{
                type   = 'section'
                fields = @(
                    @{
                        type = 'mrkdwn'
                        text = "*Timestamp:*`n" + ($Payload.TaskInfo.Timestamp | Get-Date).ToString('yyyy-MM-dd @ hh:mm:ss tt')
                    },
                    @{
                        type = 'mrkdwn'
                        text = "*Tenant:*`n" + $Payload.Tenant
                    }
                )
            })
        $Blocks.Add([PSCustomObject]@{
                type = 'divider'
            })
        foreach ($Result in $Payload.Results) {
            # Check if results is [string] and create text section
            if ($Result -is [string]) {
                $Blocks.Add([PSCustomObject]@{
                        type = 'section'
                        text = @{
                            type = 'mrkdwn'
                            text = $Result
                        }
                    })
            } else {
                #Iterate through property names and create fields
                $Fields = [system.collections.generic.list[object]]::new()
                foreach ($Key in $Result.PSObject.Properties.Name) {
                    $Fields.Add(@{
                            type = 'mrkdwn'
                            text = "*$($Key):*`n" + $Result.$Key
                        })
                }
                $Blocks.Add([PSCustomObject]@{
                        type   = 'section'
                        fields = @($Fields)

                    })
            }
        }
    } elseif ($Payload.RawData -is [object]) {
        # Webhook alert
        $Blocks.Add([PSCustomObject]@{
                type = 'header'
                text = @{
                    type  = 'plain_text'
                    text  = 'New Alert from CIPP'
                    emoji = $true
                }
            })

        $Blocks.Add([PSCustomObject]@{
                type = 'section'
                text = @{
                    type = 'mrkdwn'
                    text = "*Title:*`n" + $Payload.Title
                }
            })
        $Blocks.Add([PSCustomObject]@{
                type     = 'actions'
                elements = @(
                    @{
                        type  = 'button'
                        text  = @{
                            type = 'plain_text'
                            text = $Payload.ActionText ?? 'Go to CIPP'
                        }
                        url   = $Payload.ActionUrl
                        style = 'primary'
                    }
                )
            })
        $Blocks.Add([PSCustomObject]@{
                type = 'divider'
            })

        $Blocks.Add([PSCustomObject]@{
                type = 'section'
                text = @{
                    type = 'mrkdwn'
                    text = '*Webhook Data:*'
                }
            })
        #loop through rawdata properties and create key value fields
        $Fields = [system.collections.generic.list[object]]::new()
        foreach ($Key in $Payload.RawData.PSObject.Properties.Name) {
            # if value is json continue to next property
            if ($Payload.RawData.$Key -is [string] -and ![string]::IsNullOrEmpty($Payload.RawData.$Key)) {
                continue
            }
            # if value is date object
            if ($Payload.RawData.$Key -is [datetime]) {
                $Fields.Add(@{
                        type = 'mrkdwn'
                        text = "*$($Key):*`n" + $Payload.RawData.$Key.ToString('yyyy-MM-dd @ hh:mm:ss tt')
                    })
            } elseif ($Payload.RawData.$Key -is [array] -and $Payload.RawData.$Key.Count -gt 0) {
                foreach ($SubKey in $Payload.RawData.$Key) {
                    if ([string]::IsNullOrEmpty($SubKey)) {
                        continue
                    } elseif ($SubKey -is [datetime]) {
                        $Fields.Add(@{
                                type = 'mrkdwn'
                                text = "*$($Key):*`n" + $SubKey.ToString('yyyy-MM-dd @ hh:mm:ss tt')
                            })
                    } else {
                        $Fields.Add(@{
                                type = 'mrkdwn'
                                text = "*$($Key):*`n" + $SubKey
                            })
                    }
                }
            } elseif ($Payload.RawData.$Key.PSObject.Properties.Name -is [array] -and $Payload.RawData.$Key.PSObject.Properties.Name.Count -gt 0) {
                foreach ($SubKey in $Payload.RawData.$Key.PSObject.Properties.Name) {
                    if ([string]::IsNullOrEmpty($Payload.RawData.$Key.$SubKey)) {
                        continue
                    } elseif ($Payload.RawData.$Key.$SubKey -is [datetime]) {
                        $Fields.Add(@{
                                type = 'mrkdwn'
                                text = "*$($Key)/$($SubKey):*`n" + $Payload.RawData.$Key.$SubKey.ToString('yyyy-MM-dd @ hh:mm:ss tt')
                            })
                    } elseif (Test-Json $Payload.RawData.$Key.$SubKey -ErrorAction SilentlyContinue) {
                        # parse json and iterate through properties
                        $SubKeyData = $Payload.RawData.$Key.$SubKey | ConvertFrom-Json
                        foreach ($SubSubKey in $SubKeyData.PSObject.Properties.Name) {
                            $Fields.Add(@{
                                    type = 'mrkdwn'
                                    text = "*$($Key)/$($SubKey)/$($SubSubKey):*`n" + $SubKeyData.$SubSubKey
                                })
                        }
                    } else {
                        $Fields.Add(@{
                                type = 'mrkdwn'
                                text = "*$($Key)/$($SubKey):*`n" + $Payload.RawData.$Key.$SubKey
                            })
                    }
                }
            } else {
                $Fields.Add(@{
                        type = 'mrkdwn'
                        text = "*$($Key):*`n" + $Payload.RawData.$Key
                    })
            }
        }

        $FieldBatch = [system.collections.generic.list[object]]::new()
        for ($i = 0; $i -lt $Fields.Count; $i += 10) {
            $FieldBatch.Add($Fields[$i..[math]::Min($i + 9, $Fields.Count - 1)])
        }
        foreach ($Batch in $FieldBatch) {
            $Blocks.Add([PSCustomObject]@{
                    type   = 'section'
                    fields = @($Batch)
                })
        }

        # if potentiallocationinfo is present
        if ($Payload.PotentialLocationInfo) {
            # add divider
            $Blocks.Add([PSCustomObject]@{
                    type = 'divider'
                })
            # add text section for location
            $Blocks.Add([PSCustomObject]@{
                    type = 'section'
                    text = @{
                        type = 'mrkdwn'
                        text = '*Potential Location Info:*'
                    }
                })
            # loop through location properties and add fields
            $LocationFields = [system.collections.generic.list[object]]::new()
            foreach ($Key in $Payload.PotentialLocationInfo.PSObject.Properties.Name) {
                $LocationFields.Add(@{
                        type = 'mrkdwn'
                        text = "*$($Key):*`n" + $Payload.PotentialLocationInfo.$Key
                    })
            }
            # add fields to section in groups of 10
            $LocationFieldBatch = [system.collections.generic.list[object]]::new()
            for ($i = 0; $i -lt $LocationFields.Count; $i += 10) {
                $LocationFieldBatch.Add($LocationFields[$i..[math]::Min($i + 9, $LocationFields.Count - 1)])
            }
            foreach ($Batch in $LocationFieldBatch) {
                $Blocks.Add([PSCustomObject]@{
                        type   = 'section'
                        fields = @($Batch)
                    })
            }
        }
    }

    if (($Blocks | Measure-Object).Count -gt 0) {
        [PSCustomObject]@{
            blocks = $Blocks
        }
    }
}