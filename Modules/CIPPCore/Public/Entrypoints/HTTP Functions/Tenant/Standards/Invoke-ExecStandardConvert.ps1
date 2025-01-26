using namespace System.Net

function Invoke-ExecStandardConvert {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    function Convert-SingleStandardItem {
        param(
            [Parameter(Mandatory)]
            $OldStd
        )

        $Actions = New-Object System.Collections.ArrayList
        $RemediatePresent = ($OldStd.PSObject.Properties.Name -contains 'remediate')
        $AlertPresent = ($OldStd.PSObject.Properties.Name -contains 'alert')
        $ReportPresent = ($OldStd.PSObject.Properties.Name -contains 'report')

        $RemediateTrue = $RemediatePresent -and $OldStd.remediate -eq $true
        $AlertTrue = $AlertPresent -and $OldStd.alert -eq $true
        $ReportTrue = $ReportPresent -and $OldStd.report -eq $true

        if (-not ($RemediateTrue -or $AlertTrue -or $ReportTrue)) {
            return $null
        }

        if ($RemediateTrue) {
            [void]$Actions.Add([pscustomobject]@{label = 'Remediate'; value = 'Remediate' })
        }
        if ($AlertTrue) {
            [void]$Actions.Add([pscustomobject]@{label = 'Alert'; value = 'warn' })
        }
        if ($ReportTrue) {
            [void]$Actions.Add([pscustomobject]@{label = 'Report'; value = 'Report' })
        }

        $propsToCopy = $OldStd | Select-Object * -ExcludeProperty alert, report, remediate
        $Result = [ordered]@{}
        if ($Actions.Count -gt 0) {
            $ActionArray = $Actions | ForEach-Object { $_ }
            $Result.action = @($ActionArray)
        }

        foreach ($prop in $propsToCopy.PSObject.Properties) {
            if ($prop.Name -ne 'PSObject') {
                $Result.$($prop.Name) = $prop.Value
            }
        }

        return $Result
    }

    function Convert-OldStandardToNewFormat {
        param(
            [Parameter(Mandatory = $true)]
            $OldStandard,
            [Parameter(Mandatory = $false)]
            $AllTenantsExclusions = @()
        )

        $Tenant = $OldStandard.Tenant
        if ($Tenant -eq 'AllTenants') {
            $TenantFilter = @(
                [pscustomobject]@{
                    label       = '*All Tenants (AllTenants)'
                    value       = 'AllTenants'
                    addedFields = [pscustomobject]@{}
                }
            )
            if ($AllTenantsExclusions.Count -gt 0) {
                $Excluded = $AllTenantsExclusions | ForEach-Object {
                    [pscustomobject]@{
                        label       = "$_ ($_)"
                        value       = $_
                        addedFields = [pscustomobject]@{}
                    }
                }
            } else {
                $Excluded = $null
            }
        } else {
            $TenantFilter = @(
                [pscustomobject]@{
                    label       = "$Tenant ($Tenant)"
                    value       = $Tenant
                    addedFields = [pscustomobject]@{}
                }
            )
            $Excluded = $null
        }

        $NewStandards = [ordered]@{}

        foreach ($StdKey in $OldStandard.Standards.PSObject.Properties.Name) {
            if ($StdKey -in ('tenant', 'OverrideAllTenants', 'v2', 'v2.1')) {
                continue
            }

            $OldStd = $OldStandard.Standards.$StdKey
            $NewStdKey = if ($StdKey -eq 'ConditionalAccess') {
                Write-Host 'Converting ConditionalAccess to ConditionalAccessTemplate'
                'ConditionalAccessTemplate'
            } else { $StdKey }
            $IsArrayStandard = ($NewStdKey -eq 'IntuneTemplate' -or $NewStdKey -eq 'ConditionalAccessTemplate')
            $ConvertedObj = Convert-SingleStandardItem $OldStd
            if ($ConvertedObj -eq $null) {
                continue
            }

            if ($IsArrayStandard) {
                $FinalArray = New-Object System.Collections.ArrayList
                $TemplateList = $ConvertedObj.TemplateList
                $ConvertedObj.PSObject.Properties.Remove('TemplateList')

                if ($TemplateList -and $TemplateList.Count -gt 0) {
                    foreach ($TItem in $TemplateList) {
                        $NewItem = [ordered]@{}
                        if ($ConvertedObj.action) {
                            $NewItem.action = $ConvertedObj.action
                        }
                        foreach ($prop in $ConvertedObj.PSObject.Properties.Name) {
                            if ($prop -ne 'action') {
                                $NewItem.$prop = $ConvertedObj.$prop
                            }
                        }
                        $NewItem.TemplateList = $TItem
                        [void]$FinalArray.Add($NewItem)
                    }
                }

                if ($FinalArray.Count -gt 0) {
                    $ArrayItems = $FinalArray | ForEach-Object { $_ }
                    $NewStandards.$NewStdKey = $ArrayItems
                }
            } else {
                $Action = $ConvertedObj.action
                if ($Action) {
                    $ConvertedObj.PSObject.Properties.Remove('action')
                }
                $Wrap = [ordered]@{}
                if ($Action) {
                    $Wrap.action = $Action
                }
                $Wrap.standards = [ordered]@{}
                $Wrap.standards.$NewStdKey = $ConvertedObj
                $NewStandards.$NewStdKey = $Wrap
            }

        }

        $NewTemplate = [pscustomobject]@{
            tenantFilter = $TenantFilter
            templateName = "Converted Legacy Template for $Tenant"
            standards    = $NewStandards
            runManually  = $true
        }

        if ($Tenant -eq 'AllTenants' -and $Excluded) {
            $ExcludedArr = $Excluded | ForEach-Object { $_ }
            $NewTemplate | Add-Member -NotePropertyName 'excludedTenants' -NotePropertyValue @($ExcludedArr) -Force
        }

        return $NewTemplate
    }

    $Table = Get-CippTable -tablename 'standards'
    $Filter = "PartitionKey eq 'standards'"
    $OldStandards = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json

    $AllTenantsStd = $OldStandards | Where-Object { $_.Tenant -eq 'AllTenants' }
    $HasAllTenants = $AllTenantsStd -ne $null

    $AllTenantsExclusions = New-Object System.Collections.ArrayList
    $StandardsToConvert = New-Object System.Collections.ArrayList

    foreach ($OldStd in $OldStandards) {
        $Tenant = $OldStd.Tenant
        $StdNames = $OldStd.Standards.PSObject.Properties.Name | Where-Object { $_ -notin ('tenant', 'OverrideAllTenants', 'v2', 'v2.1') }
        $HasOverride = ($OldStd.Standards.PSObject.Properties.Name -contains 'OverrideAllTenants')

        if ($Tenant -ne 'AllTenants') {
            if ($HasOverride -and $StdNames.Count -eq 0) {
                [void]$AllTenantsExclusions.Add($Tenant)
                continue
            }

            if ($HasOverride -and $StdNames.Count -gt 0 -and $HasAllTenants) {
                [void]$AllTenantsExclusions.Add($Tenant)
            }
        }

        [void]$StandardsToConvert.Add($OldStd)
    }

    foreach ($OldStd in $StandardsToConvert) {
        $Converted = Convert-OldStandardToNewFormat $OldStd ($AllTenantsExclusions)
        $GUID = [guid]::NewGuid()
        $Converted | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $GUID -Force
        $Converted | Add-Member -NotePropertyName 'createdAt' -NotePropertyValue ((Get-Date).ToUniversalTime()) -Force
        $Converted | Add-Member -NotePropertyName 'updatedBy' -NotePropertyValue 'System' -Force
        $Converted | Add-Member -NotePropertyName 'updatedAt' -NotePropertyValue (Get-Date).ToUniversalTime() -Force
        $JSON = ConvertTo-Json -Depth 100 -InputObject $Converted -Compress

        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        if ($Converted.standards) {
            Add-CIPPAzDataTableEntity @Table -Entity @{
                JSON         = "$JSON"
                RowKey       = "$GUID"
                PartitionKey = 'StandardsTemplateV2'
                GUID         = "$GUID"
            }
        }
    }

    #delete the old standards
    if ($StandardsToConvert.Count -gt 0) {
        $StandardsToConvert | ForEach-Object {
            $Table = Get-CippTable -tablename 'standards'
            $OldStdsTableItems = Get-CIPPAzDataTableEntity @Table -Filter $Filter
            try {
                Remove-AzDataTableEntity @Table -Entity $OldStdsTableItems -Force
            } catch {
                #donothing
            }
        }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = 'Successfully converted legacy standards to new format'
        })
}
