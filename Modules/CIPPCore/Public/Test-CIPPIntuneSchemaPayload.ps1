function Test-CIPPIntuneSchemaPayload {
    <#
    .SYNOPSIS
        Checks a classic Intune policy payload against the property types Graph declares.
    .DESCRIPTION
        Walks the payload against Config/intune-graph-schema.json (generated from the vendored Graph
        metadata by build/tools/Update-IntuneGraphSchema.ps1) and returns a finding for each property
        Graph does not define and each value that is not the declared type: text where a boolean or
        number belongs, an enum value Graph does not list, an object where a list belongs.

        Every finding is a warning, because the vendored schema can lag Intune. Values holding a
        %variable% are not checked; they are resolved at deployment. Settings Catalog and
        administrative template payloads are not described by this schema and return nothing.
    .EXAMPLE
        Test-CIPPIntuneSchemaPayload -Policy $Policy -TemplateType 'windowsFeatureUpdateProfiles'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory = $true)]
        $Policy,
        [Parameter(Mandatory = $true)]
        [string]$TemplateType
    )

    # Static for the life of the process; parsed on first use.
    if (-not $script:CIPPIntuneGraphSchema) {
        $SchemaPath = Join-Path -Path $env:CIPPRootPath -ChildPath 'Config/intune-graph-schema.json'
        $script:CIPPIntuneGraphSchema = [System.IO.File]::ReadAllText($SchemaPath) | ConvertFrom-Json -AsHashtable
    }
    $Schema = $script:CIPPIntuneGraphSchema

    $RootType = $Schema.templateTypes[$TemplateType]
    if (-not $RootType) { return @() }

    $IntegerTypes = @('Edm.Int16', 'Edm.Int32', 'Edm.Int64', 'Edm.Byte')
    $NumberTypes = @('Edm.Double', 'Edm.Single', 'Edm.Decimal')
    $Findings = [System.Collections.Generic.List[pscustomobject]]::new()

    $Pending = [System.Collections.Generic.Stack[object[]]]::new()
    $Pending.Push(@($Policy, $RootType, ''))
    while ($Pending.Count -gt 0) {
        $Node, $TypeName, $NodePath = $Pending.Pop()

        # A node's own @odata.type wins: a payload can carry a subtype where its parent declares the base.
        $OwnType = $Node.'@odata.type'
        if ($OwnType -is [string]) { $TypeName = $OwnType.TrimStart('#') }
        $Declared = $Schema.types[$TypeName]
        if (-not $Declared) {
            $Findings.Add([pscustomobject]@{
                    Severity = 'Warning'; Code = 'UnknownODataType'; Path = $NodePath ? "$NodePath.@odata.type" : '@odata.type'
                    Message  = "The type $TypeName is not in CIPP's copy of the Graph schema, so its settings were not checked."
                })
            continue
        }

        foreach ($Property in $Node.PSObject.Properties) {
            $Name = $Property.Name
            if ($Name.Contains('@odata')) { continue }
            $Path = $NodePath ? "$NodePath.$Name" : $Name

            $Type = $Declared[$Name]
            if (-not $Type) {
                $Findings.Add([pscustomobject]@{
                        Severity = 'Warning'; Code = 'UnknownProperty'; Path = $Path
                        Message  = "'$Path' is not a setting Graph defines for $($TypeName -replace '^microsoft\.graph\.'). Intune ignores or rejects settings it does not define, so it never reaches the tenant and compare and drift report it as different. If the setting is new, CIPP's copy of the Graph schema may not know it yet."
                    })
                continue
            }

            $Value = $Property.Value
            if ($null -eq $Value) { continue }

            $IsCollection = $Type.StartsWith('Collection(')
            $Inner = $IsCollection ? $Type.Substring(11, $Type.Length - 12) : $Type
            if ($IsCollection -and -not ($Value -is [System.Collections.IList])) {
                $Findings.Add([pscustomobject]@{
                        Severity = 'Warning'; Code = 'WrongType'; Path = $Path
                        Message  = "'$Path' holds a single value where Intune expects a list."
                    })
                continue
            }

            $Enum = $Schema.enums[$Inner]
            $Index = 0
            foreach ($Item in ($IsCollection ? $Value : @(, $Value))) {
                $ItemPath = $IsCollection ? "$Path[$Index]" : $Path
                $Index++
                if ($null -eq $Item) { continue }
                if ($Item -is [string] -and $Item -match '%[^%\s]+%') { continue }

                $Code = $null
                $Expected = $null
                if ($Inner -eq 'Edm.Boolean') {
                    if ($Item -is [bool]) { continue }
                    if ($Item -is [string] -and $Item -in 'true', 'false') { $Code = 'TextBoolean' }
                    $Expected = 'true or false'
                } elseif ($Inner -in $IntegerTypes) {
                    if ($Item -is [int] -or $Item -is [long]) { continue }
                    if ($Item -is [string] -and $Item -match '^-?\d+$') { $Code = 'TextNumber' }
                    $Expected = 'a whole number'
                } elseif ($Inner -in $NumberTypes) {
                    if ($Item -is [int] -or $Item -is [long] -or $Item -is [double] -or $Item -is [decimal]) { continue }
                    $Expected = 'a number'
                } elseif ($Inner -eq 'Edm.DateTimeOffset') {
                    # ConvertFrom-Json turns an ISO 8601 string into a DateTime.
                    if ($Item -is [datetime] -or $Item -is [datetimeoffset]) { continue }
                    $Parsed = [datetimeoffset]::MinValue
                    if ($Item -is [string] -and [datetimeoffset]::TryParse($Item, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$Parsed)) { continue }
                    $Expected = 'a date and time, such as 2026-12-01T09:00:00Z'
                } elseif ($Enum) {
                    if ($Item -is [string]) {
                        $Parts = $Enum.flags ? $Item.Split(',').Trim() : @($Item)
                        $Unknown = @(foreach ($Part in $Parts) { if ($Part -notin $Enum.members) { $Part } })
                        if ($Unknown.Count -eq 0) { continue }
                        $Findings.Add([pscustomobject]@{
                                Severity = 'Warning'; Code = 'UnknownEnumValue'; Path = $ItemPath
                                Message  = "'$ItemPath' is set to '$($Unknown -join ', ')', which is not a value Intune accepts here. Accepted values: $($Enum.members -join ', ')."
                            })
                        continue
                    }
                    $Expected = "one of: $($Enum.members -join ', ')"
                } elseif ($Schema.types.ContainsKey($Inner)) {
                    if ($Item -is [System.Management.Automation.PSCustomObject] -or $Item -is [System.Collections.IDictionary]) {
                        $Pending.Push(@($Item, $Inner, $ItemPath))
                        continue
                    }
                    $Expected = 'a group of settings'
                } else {
                    # Text types: strings, GUIDs, durations, binary, dates without a time.
                    if ($Item -is [string] -or $Item -is [datetime]) { continue }
                    $Expected = 'text'
                }

                $Shown = $Item -is [string] ? "the text '$Item'" : "'$Item'"
                $Message = switch ($Code) {
                    'TextBoolean' { "'$ItemPath' holds the text '$Item' where Intune expects true or false. It deploys, but compare and drift report it as different from the tenant. Open the template in the editor and save it to store it as true or false." }
                    'TextNumber' { "'$ItemPath' holds the number as text ('$Item'). Open the template in the editor and save it to store it as a number." }
                    default { "'$ItemPath' holds $Shown where Intune expects $Expected." }
                }
                $Findings.Add([pscustomobject]@{ Severity = 'Warning'; Code = $Code ?? 'WrongType'; Path = $ItemPath; Message = $Message })
            }
        }
    }

    return @($Findings)
}
