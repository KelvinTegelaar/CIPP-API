function Invoke-ListIntuneTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CippTable -tablename 'templates'
    $Imported = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'settings'"
    if ($Imported.IntuneTemplate -ne $true) {
        $Templates = Get-ChildItem 'Config\*.IntuneTemplate.json' | ForEach-Object {
            $Entity = @{
                JSON         = "$(Get-Content $_)"
                RowKey       = "$($_.name)"
                PartitionKey = 'IntuneTemplate'
                GUID         = "$($_.name)"
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
        }
        Add-CIPPAzDataTableEntity @Table -Entity @{
            IntuneTemplate = $true
            RowKey         = 'IntuneTemplate'
            PartitionKey   = 'settings'
        } -Force
    }
    #List new policies
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'IntuneTemplate'"
    $RawTemplates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter)
    if ($Request.query.View) {
        $Templates = $RawTemplates | ForEach-Object {
            try {
                $JSONData = $_.JSON | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
                $data = $JSONData.RAWJson | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
                $data | Add-Member -NotePropertyName 'displayName' -NotePropertyValue $JSONData.Displayname -Force
                $data | Add-Member -NotePropertyName 'description' -NotePropertyValue $JSONData.Description -Force
                $data | Add-Member -NotePropertyName 'Type' -NotePropertyValue $JSONData.Type -Force
                $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.RowKey -Force
                $data | Add-Member -NotePropertyName 'package' -NotePropertyValue $_.Package -Force
                $data | Add-Member -NotePropertyName 'isSynced' -NotePropertyValue (![string]::IsNullOrEmpty($_.SHA))
                $data
            } catch {

            }

        } | Sort-Object -Property displayName
    } else {
        if ($Request.query.mode -eq 'Tag') {
            #when the mode is tag, show all the potential tags, return the object with: label: tag, value: tag, count: number of templates with that tag, unique only
            $Templates = $RawTemplates | Where-Object { $_.Package } | Select-Object -Property Package | ForEach-Object {
                $package = $_.Package
                [pscustomobject]@{
                    label         = "$($package) ($(($RawTemplates | Where-Object { $_.Package -eq $package }).Count) Templates)"
                    value         = $package
                    type          = 'tag'
                    templateCount = ($RawTemplates | Where-Object { $_.Package -eq $package }).Count
                    templates     = @($RawTemplates | Where-Object { $_.Package -eq $package } | ForEach-Object {
                            try {
                                $JSONData = $_.JSON | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
                                $data = $JSONData.RAWJson | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
                                $data | Add-Member -NotePropertyName 'displayName' -NotePropertyValue $JSONData.Displayname -Force
                                $data | Add-Member -NotePropertyName 'description' -NotePropertyValue $JSONData.Description -Force
                                $data | Add-Member -NotePropertyName 'Type' -NotePropertyValue $JSONData.Type -Force
                                $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.RowKey -Force
                                $data | Add-Member -NotePropertyName 'package' -NotePropertyValue $_.Package -Force
                                $data
                            } catch {

                            }
                        })
                }
            } | Sort-Object -Property label -Unique
        } else {
            $Templates = $RawTemplates.JSON | ForEach-Object { try { ConvertFrom-Json -InputObject $_ -Depth 100 -ErrorAction SilentlyContinue } catch {} }

        }
    }

    if ($Request.query.ID) { $Templates = $Templates | Where-Object -Property guid -EQ $Request.query.id }

    # Sort all output regardless of view condition
    $Templates = $Templates | Sort-Object -Property displayName

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ConvertTo-Json -Depth 100 -InputObject @($Templates)
        })

}
