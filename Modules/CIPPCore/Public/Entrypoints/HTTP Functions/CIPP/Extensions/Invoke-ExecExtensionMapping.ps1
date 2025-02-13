using namespace System.Net

Function Invoke-ExecExtensionMapping {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Extension.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    $Table = Get-CIPPTable -TableName CippMapping

    if ($Request.Query.List) {
        switch ($Request.Query.List) {
            'HaloPSA' {
                $body = Get-HaloMapping -CIPPMapping $Table
            }
            'NinjaOne' {
                $Body = Get-NinjaOneOrgMapping -CIPPMapping $Table
            }
            'NinjaOneFields' {
                $Body = Get-NinjaOneFieldMapping -CIPPMapping $Table
            }
            'Hudu' {
                $Body = Get-HuduMapping -CIPPMapping $Table
            }
            'HuduFields' {
                $Body = Get-HuduFieldMapping -CIPPMapping $Table
            }
            'Sherweb' {
                $Body = Get-SherwebMapping -CIPPMapping $Table
            }
            'HaloPSAFields' {
                $TicketTypes = Get-HaloTicketType
                $Body = @{'TicketTypes' = $TicketTypes }
            }
            'PWPushFields' {
                $Accounts = Get-PwPushAccount
                $Body = @{
                    'Accounts' = $Accounts
                }
            }
        }
    }

    try {
        if ($Request.Query.AddMapping) {
            switch ($Request.Query.AddMapping) {
                'Sherweb' {
                    $Body = Set-SherwebMapping -CIPPMapping $Table -APIName $APIName -Request $Request
                }
                'HaloPSA' {
                    $body = Set-HaloMapping -CIPPMapping $Table -APIName $APIName -Request $Request
                }
                'NinjaOne' {
                    $Body = Set-NinjaOneOrgMapping -CIPPMapping $Table -APIName $APIName -Request $Request
                }
                'NinjaOneFields' {
                    $Body = Set-NinjaOneFieldMapping -CIPPMapping $Table -APIName $APIName -Request $Request -TriggerMetadata $TriggerMetadata
                }
                'Hudu' {
                    $Body = Set-HuduMapping -CIPPMapping $Table -APIName $APIName -Request $Request
                    Register-CIPPExtensionScheduledTasks
                }
                'HuduFields' {
                    $Body = Set-ExtensionFieldMapping -CIPPMapping $Table -APIName $APIName -Request $Request -Extension 'Hudu'
                    Register-CIPPExtensionScheduledTasks
                }
            }
        }
    } catch {
        Write-LogMessage -API $APINAME -headers $Request.Headers -message "mapping API failed. $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
    }

    try {
        if ($Request.Query.AutoMapping) {
            switch ($Request.Query.AutoMapping) {
                'NinjaOne' {
                    $Batch = [PSCustomObject]@{
                        'NinjaAction'  = 'StartAutoMapping'
                        'FunctionName' = 'NinjaOneQueue'
                    }
                    $InputObject = [PSCustomObject]@{
                        OrchestratorName = 'NinjaOneOrchestrator'
                        Batch            = @($Batch)
                    }
                    #Write-Host ($InputObject | ConvertTo-Json)
                    $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
                    Write-Host "Started permissions orchestration with ID = '$InstanceId'"
                    $Body = [pscustomobject]@{'Results' = 'Automapping Request has been queued. Exact name matches will appear first and matches on device names and serials will take longer. Please check the CIPP Logbook and refresh the page once complete.' }
                }

            }
        }
    } catch {
        Write-LogMessage -API $APINAME -headers $Request.Headers -message "mapping API failed. $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
