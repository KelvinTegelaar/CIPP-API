function Push-BPACollectData {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    param($Item)

    $TenantName = Get-Tenants | Where-Object -Property defaultDomainName -EQ $Item.Tenant
    $BPATemplateTable = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'BPATemplate'"
    $TemplatesLoc = (Get-CIPPAzDataTableEntity @BPATemplateTable -Filter $Filter).JSON | ConvertFrom-Json

    $Templates = $TemplatesLoc | ForEach-Object {
        $Template = $_
        [PSCustomObject]@{
            Data  = $Template
            Name  = $Template.Name
            Style = $Template.Style
        }
    }
    $Table = Get-CippTable -tablename 'cachebpav2'

    $Rerun = Test-CIPPRerun -Type 'BPA' -Tenant $Item.Tenant -API $Item.Template
    if ($Rerun) {
        Write-Host 'Detected rerun for BPA. Exiting cleanly'
        exit 0
    }
    Write-Host "Working on BPA for $($TenantName.defaultDomainName) with GUID $($TenantName.customerId) - Report ID $($Item.Template)"
    $Template = $Templates | Where-Object -Property Name -EQ -Value $Item.Template
    # Build up the result object that will be stored in tables
    $Result = @{
        Tenant       = "$($TenantName.displayName)"
        GUID         = "$($TenantName.customerId)"
        RowKey       = "$($Template.Name)"
        PartitionKey = "$($TenantName.customerId)"
        LastRefresh  = [string]$(Get-Date (Get-Date).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%S.000Z')
    }
    foreach ($field in $Template.Data.Fields) {
        if ($field.UseExistingInfo) { continue }
        if ($Field.Where) { $filterscript = [scriptblock]::Create($Field.Where) } else { $filterscript = { $true } }
        try {
            switch ($field.API) {
                'Graph' {
                    $paramsField = @{
                        uri      = $field.URL
                        tenantid = $TenantName.defaultDomainName
                    }
                    if ($Field.Parameters.PSObject.properties.name) {
                        $field.Parameters | ForEach-Object {
                            $paramsField[$_.PSObject.properties.name] = $_.PSObject.properties.value
                        }
                    }
                    $FieldInfo = New-GraphGetRequest @paramsField | Where-Object $filterscript | Select-Object $field.ExtractFields
                }
                'Exchange' {
                    Write-Host "Trying to execute $($field.Command) for $($TenantName.displayName) with GUID $($TenantName.customerId)"
                    if ($field.Command -notlike 'get-*') {
                        Write-LogMessage -API 'BPA' -tenant $TenantName.defaultDomainName -message 'The BPA only supports get- exchange commands. A set or update command was used.' -sev Error
                        break
                    } else {
                        $paramsField = @{
                            tenantid = $TenantName.defaultDomainName
                            cmdlet   = $field.Command
                        }
                        if ($Field.Parameters) { $paramsField.'cmdParams' = $field.parameters }
                        $FieldInfo = New-ExoRequest @paramsField | Where-Object $filterscript | Select-Object $field.ExtractFields
                    }
                }
                'CIPPFunction' {
                    if ($field.Command -notlike 'get-CIPP*') {
                        Write-LogMessage -API 'BPA' -tenant $TenantName.defaultDomainName -message 'The BPA only supports get-CIPP commands. A set or update command was used, or a command that is not allowed.' -sev Error
                        break
                    }
                    $paramsField = @{
                        TenantFilter = $TenantName.defaultDomainName
                    }
                    if ($field.Parameters.PSObject.properties.name) {
                        $field.Parameters | ForEach-Object {
                            $paramsField[$_.PSObject.properties.name] = $_.PSObject.properties.value
                        }
                    }
                    $FieldInfo = & $field.Command @paramsField | Where-Object $filterscript | Select-Object $field.ExtractFields
                }
            }
        } catch {
            Write-Information "Error getting $($field.Name) in $($field.api) for $($TenantName.displayName) with GUID $($TenantName.customerId). Error: $($_.Exception.Message)"
            Write-LogMessage -API 'BPA' -tenant $TenantName.defaultDomainName -message "Error getting $($field.Name) for $($TenantName.displayName) with GUID $($TenantName.customerId). Error: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
            $FieldInfo = 'FAILED'
            $field.StoreAs = 'string'
        }
        try {
            switch -Wildcard ($field.StoreAs) {
                '*bool' {
                    if ($field.ExtractFields.Count -gt 1) {
                        Write-LogMessage -API 'BPA' -tenant $TenantName.defaultDomainName -message "The BPA only supports 1 field for a bool. $($field.ExtractFields.Count) fields were specified." -sev Error
                        break
                    }
                    if ($null -eq $FieldInfo.$($field.ExtractFields)) { $FieldInfo = $false }

                    $Result.Add($field.Name, [bool]$FieldInfo.$($field.ExtractFields))
                }
                'JSON' {
                    if ($null -eq $FieldInfo) { $JsonString = '{}' } else { $JsonString = (ConvertTo-Json -Depth 15 -InputObject $FieldInfo -Compress) }
                    Write-Host "Adding $($field.Name) to table with value $JsonString"
                    $Result.Add($field.Name, $JSONString)
                }
                'string' {
                    $Result.Add($field.Name, [string]$FieldInfo)
                }
                'percentage' {

                }
            }
        } catch {
            Write-LogMessage -API 'BPA' -tenant $TenantName.defaultDomainName -message "Error storing $($field.Name) for $($TenantName.displayName) with GUID $($TenantName.customerId). Error: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
            $Result.Add($field.Name, 'FAILED')
        }

    }

    if ($Result) {
        try {
            Add-CIPPAzDataTableEntity @Table -Entity $Result -Force
        } catch {
            Write-LogMessage -API 'BPA' -tenant $TenantName.defaultDomainName -message "Error getting saving data for $($template.Name) - $($TenantName.customerId). Error: $($_.Exception.Message)" -LogData (Get-CippException -Exception $_) -sev Error
        }
    }
}
