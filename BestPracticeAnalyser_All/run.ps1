param($tenant)

$TenantName = Get-Tenants | Where-Object -Property defaultDomainName -EQ $tenant
Set-Location (Get-Item $PSScriptRoot).Parent.FullName
$TemplatesLoc = Get-ChildItem "Config\*.BPATemplate.json"
$Templates = $TemplatesLoc | ForEach-Object {
    $Template = $(Get-Content $_) | ConvertFrom-Json
    [PSCustomObject]@{
        Data  = $Template
        Name  = $Template.Name
        Style = $Template.Style
    }
}
$Table = Get-CippTable -tablename 'cachebpav2'
$AddRow = foreach ($Template in $templates) {
    # Build up the result object that will be passed back to the durable function
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
                "Graph" { 
                    $paramsField = @{
                        uri      = $field.URL
                        tenantid = $TenantName.defaultDomainName
                    }
                    if ($Field.parameters) {
                        $field.Parameters | ForEach-Object {
                            Write-Host "Doing: $($_.psobject.properties.name) with value $($_.psobject.properties.value)"
                            $paramsField.Add($_.psobject.properties.name, $_.psobject.properties.value)
                        }
                    }
                    $FieldInfo = New-GraphGetRequest @paramsField | Where-Object $filterscript | Select-Object $field.ExtractFields
                }
                "Exchange" {
                    if ($field.Command -notlike "get-*") {
                        Write-LogMessage  -API "BPA" -tenant $tenant -message "The BPA only supports get- exchange commands. A set or update command was used." -sev Error
                        break
                    }
                    else {
                        $paramsField = @{
                            tenantid = $TenantName.defaultDomainName
                            cmdlet   = $field.Command
                        }
                        if ($Field.Parameters) { $paramsfield.add('cmdparams', $field.parameters) }
                        $FieldInfo = New-ExoRequest @paramsField | Where-Object $filterscript | Select-Object $field.ExtractFields 
                    }
                }
                "CIPPFunction" {
                    if ($field.Command -notlike "get-CIPP*") {
                        Write-LogMessage  -API "BPA" -tenant $tenant -message "The BPA only supports get-CIPP commands. A set or update command was used, or a command that is not allowed." -sev Error
                        break
                    }
                    $paramsField = @{
                        TenantFilter = $TenantName.defaultDomainName
                    }
                    if ($field.parameters) {
                        $field.Parameters | ForEach-Object {
                            $paramsField.Add($_.psobject.properties.name, $_.psobject.properties.value)
                        }
                    }
                    $FieldInfo = & $field.Command @paramsField | Where-Object $filterscript  | Select-Object $field.ExtractFields 
                }
            }
        }
        catch {
            Write-Host "Error getting $($field.Name) in $($field.api) for $($TenantName.displayName) with GUID $($TenantName.customerId). Error: $($_.Exception.Message)"
            Write-LogMessage -API "BPA" -tenant $tenant -message "Error getting $($field.Name) for $($TenantName.displayName) with GUID $($TenantName.customerId). Error: $($_.Exception.Message)" -sev Error
            $fieldinfo = "FAILED"
            $field.StoreAs = "string"
        } 
        try {
            switch -Wildcard ($field.StoreAs) {
                "*bool" {
                    if ($field.ExtractFields.Count -gt 1) {
                        Write-LogMessage  -API "BPA" -tenant $tenant -message "The BPA only supports 1 field for a bool. $($field.ExtractFields.Count) fields were specified." -sev Error
                        break
                    }
                    if ($null -eq $FieldInfo.$($field.ExtractFields)) { $FieldInfo = $false }

                    $Result.Add($field.Name, [bool]$FieldInfo.$($field.ExtractFields))
                }
                "JSON" {
                    if ($FieldInfo -eq $null) { $JsonString = '{}' } else { $JsonString = (ConvertTo-Json -Depth 15 -InputObject $FieldInfo) }
                    $Result.Add($field.Name, $JSONString)
                }
                "string" {
                    $Result.Add($field.Name, [string]$FieldInfo)
                }
            }
        }
        catch {
            Write-LogMessage -API "BPA" -tenant $tenant -message "Error storing $($field.Name) for $($TenantName.displayName) with GUID $($TenantName.customerId). Error: $($_.Exception.Message)" -sev Error
            $Result.Add($field.Name, "FAILED")
        }

    }
 
    if ($Result) {
        try {
            Add-AzDataTableEntity @Table -Entity $Result -Force
        }
        catch {
            Write-LogMessage -API "BPA" -tenant $tenant -message "Error getting saving data for $($template.Name) - $($TenantName.customerId). Error: $($_.Exception.Message)" -sev Error

        }
    }
}
