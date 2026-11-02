function Resolve-CippReportDataToken {
    <#
    .SYNOPSIS
        Resolve &data tokens& in report builder blocks against the reporting database.
    .DESCRIPTION
        A block's text can name reporting-database data with a token, and the value is read here on
        the server when the report renders, so a scheduled run and a preview read the same data:

          &Users&                              the number of rows in that collection
          &Users.displayName&                  the field's distinct values, comma-separated (the first 25)
          &Devices.complianceState=compliant&  the number of rows whose field has that value (* wildcards; != for the rest)
          &Mailboxes.TotalItemSize:sum&        a numeric field's sum, avg, min, max or count of rows carrying it

        Collection names are the reporting database's types, the same names the Database Data block
        offers as sources; fields are case-insensitive and may reach into nested objects with dots.
        A chart with a chartSource of &Devices.operatingSystem& gets one slice per value of that field;
        a table with a dataSource of &Mailboxes& (a filter token works too) gets the rows, each column
        reading the field it names (its `field`, else its header). A score card block with a statsSource
        gets one card per value of the field (a count, or an aggregate of a numeric field) and a progress
        block with an itemsSource one bar each, filled by its share of the total. A token that names
        nothing is left as written, so the mistake shows in the report instead of silently blanking.
    .PARAMETER Blocks
        The enriched blocks, as objects or hashtables. Returned with the tokens replaced in place.
    .PARAMETER TenantFilter
        The tenant whose reporting database answers.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Blocks = @(),
        [Parameter(Mandatory = $true)][string]$TenantFilter
    )

    $Pattern = '(?:&amp;|&)(?<type>[A-Za-z0-9_-]+)(?:\.(?<field>[A-Za-z0-9_.-]+))?(?:(?<op>!=|=)(?<value>[^&]*?))?(?::(?<agg>sum|avg|min|max|count))?(?:&amp;|&)'
    $MaxListed = 25
    $MaxSlices = 8
    $MaxPoints = 30
    $MaxRows = 200

    # One read per collection per render; a collection the database does not hold reads as $null. The
    # reserved collection 'TestResults' reads the in-app compliance test results (CippTestResults) instead
    # of the reporting database, so a chart/table/flow can be driven by test data (count by Status,
    # Category, Risk...) the same way it is driven by reporting collections.
    $Cache = @{}
    $RowsOf = {
        param([string]$Type)
        $Key = $Type.ToLowerInvariant()
        if (-not $Cache.ContainsKey($Key)) {
            $Rows = try {
                if ($Key -eq 'testresults') {
                    @((Get-CIPPTestResults -TenantFilter $TenantFilter).TestResults) | Where-Object { $null -ne $_ }
                } else {
                    @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Type) | Where-Object { $null -ne $_ -and $_ -ne $false }
                }
            } catch { $null }
            $Cache[$Key] = if ($null -eq $Rows) { $null } else { @($Rows) }
        }
        $Cache[$Key]
    }

    # A field's values in one row, following a dotted path and flattening arrays along the way.
    $ValueOf = {
        param($Row, [string]$Path)
        $Current = @($Row)
        foreach ($Segment in $Path.Split('.')) {
            $Current = @(foreach ($Item in $Current) {
                    if ($null -eq $Item) { continue }
                    if ($Item -is [System.Collections.IDictionary]) {
                        $Name = @($Item.Keys) | Where-Object { "$_" -ieq $Segment } | Select-Object -First 1
                        if ($null -ne $Name) { $Item[$Name] }
                    } else {
                        $Property = $Item.PSObject.Properties | Where-Object { $_.Name -ieq $Segment } | Select-Object -First 1
                        if ($Property) { $Property.Value }
                    }
                })
        }
        @($Current | Where-Object { $null -ne $_ -and "$_" -ne '' })
    }

    $RowMatches = {
        param($Row, [string]$Field, [string]$Op, [string]$Wanted)
        $Values = @(& $ValueOf $Row $Field | ForEach-Object { "$_" })
        $Hit = if ($Wanted.Contains('*')) { @($Values | Where-Object { $_ -like $Wanted }).Count -gt 0 } else { @($Values | Where-Object { $_ -ieq $Wanted }).Count -gt 0 }
        if ($Op -eq '!=') { -not $Hit } else { $Hit }
    }

    $FormatNumber = { param([double]$n) if ([math]::Round($n) -eq $n) { "$([long]$n)" } else { "$([math]::Round($n, 2))" } }

    # The text a token stands for; $null when its collection is unknown, so the token stays as written.
    $Evaluate = {
        param($Match)
        $Type = $Match.Groups['type'].Value
        $Field = $Match.Groups['field'].Value
        $Op = $Match.Groups['op'].Value
        $Wanted = $Match.Groups['value'].Value
        $Agg = $Match.Groups['agg'].Value
        $Rows = & $RowsOf $Type
        if ($null -eq $Rows) { return $null }
        if (-not $Field) { return "$($Rows.Count)" }
        if ($Op) { return "$(@($Rows | Where-Object { & $RowMatches $_ $Field $Op $Wanted }).Count)" }
        $Values = @(foreach ($Row in $Rows) { & $ValueOf $Row $Field })
        if ($Agg) {
            if ($Agg -eq 'count') { return "$($Values.Count)" }
            $Numbers = @($Values | ForEach-Object { $_ -as [double] } | Where-Object { $null -ne $_ })
            if ($Numbers.Count -eq 0) { return '0' }
            $Measured = $Numbers | Measure-Object -Sum -Average -Minimum -Maximum
            $Aggregate = switch ($Agg) { 'sum' { $Measured.Sum } 'avg' { $Measured.Average } 'min' { $Measured.Minimum } default { $Measured.Maximum } }
            return (& $FormatNumber $Aggregate)
        }
        $Distinct = @($Values | ForEach-Object { "$_" } | Sort-Object -Unique)
        if ($Distinct.Count -le $MaxListed) { return ($Distinct -join ', ') }
        return (($Distinct | Select-Object -First $MaxListed) -join ', ') + " and $($Distinct.Count - $MaxListed) more"
    }

    # Replace every token in a string. A string that is one token and resolves to a number becomes a
    # number, so a progress bar's value or a chart point can be a token too.
    $ReplaceIn = {
        param([string]$Text)
        if ($Text -notmatch '&') { return $Text }
        $Whole = [regex]::Match($Text.Trim(), "^$Pattern$")
        $Result = [regex]::Replace($Text, $Pattern, [System.Text.RegularExpressions.MatchEvaluator] {
                param($m)
                $Value = & $Evaluate $m
                if ($null -eq $Value) { $m.Value } else { $Value }
            })
        if ($Whole.Success -and $Result.Trim() -match '^-?\d+(\.\d+)?$') { return [double]$Result.Trim() }
        $Result
    }

    $SetProperty = {
        param($Target, [string]$Name, $Value)
        if ($Target -is [System.Collections.IDictionary]) { $Target[$Name] = $Value } else { $Target | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
    }

    # Walk a value: strings are resolved, lists and objects walked, everything else kept.
    $Walk = $null
    $Walk = {
        param($Value)
        if ($Value -is [string]) { return (& $ReplaceIn $Value) }
        if ($Value -is [System.Collections.IDictionary]) {
            foreach ($Name in @($Value.Keys)) { $Value[$Name] = & $Walk $Value[$Name] }
            return $Value
        }
        if ($Value -is [array] -or $Value -is [System.Collections.IList]) {
            return , @(foreach ($Item in $Value) { & $Walk $Item })
        }
        if ($Value -is [System.Management.Automation.PSCustomObject]) {
            foreach ($Property in @($Value.PSObject.Properties)) { $Value.($Property.Name) = & $Walk $Property.Value }
            return $Value
        }
        $Value
    }

    $ParseToken = { param([string]$Text) $m = [regex]::Match("$Text".Trim(), "^$Pattern$"); if ($m.Success) { $m } }

    # A chart or table source as the builder's picker saves it - { type; field; filter = { field; op;
    # value } } - or as a token; either way @{ type; field; filter }, with filter $null when there is none.
    $SourceOf = {
        param($Source)
        if ($null -eq $Source) { return $null }
        if ($Source -is [string]) {
            $m = & $ParseToken $Source
            if (-not $m) { return $null }
            $Field = $m.Groups['field'].Value
            if ($m.Groups['op'].Value) {
                return @{ type = $m.Groups['type'].Value; field = $null; filter = @{ field = $Field; op = $m.Groups['op'].Value; value = $m.Groups['value'].Value } }
            }
            return @{ type = $m.Groups['type'].Value; field = $(if ($Field) { $Field }); filter = $null }
        }
        if (-not $Source.type) { return $null }
        $Filter = $Source.filter
        $Spec = if ($Filter -and $Filter.field -and $Filter.op) { @{ field = "$($Filter.field)"; op = "$($Filter.op)"; value = "$($Filter.value)" } }
        @{
            type       = "$($Source.type)"
            field      = $(if ($Source.field) { "$($Source.field)" })
            # a numeric field to plot instead of counting rows; aggregate combines rows sharing a label
            valueField = $(if ($Source.valueField -and "$($Source.valueField)" -ne '__count') { "$($Source.valueField)" })
            aggregate  = $(if ($Source.aggregate -and @('sum', 'avg', 'max', 'min') -contains "$($Source.aggregate)") { "$($Source.aggregate)" })
            # divide plotted values by this before drawing, so bytes can be shown as GB and so on
            scale      = $(if (($Source.scale -as [double]) -gt 0) { [double]$Source.scale })
            filter     = $Spec
        }
    }
    $RowsFor = {
        param($Spec)
        $Rows = & $RowsOf $Spec.type
        if ($null -eq $Rows) { return $null }
        if ($Spec.filter) { $Rows = @($Rows | Where-Object { & $RowMatches $_ $Spec.filter.field $Spec.filter.op $Spec.filter.value }) }
        , @($Rows)
    }

    # Label/value pairs from a source, for score cards and progress bars: one entry per distinct value
    # of the field (a count of rows, or an aggregate of a numeric field), or a single figure when no
    # field is named. Sorted by value and capped so a row of cards or bars stays readable.
    $CardsFrom = {
        param($Spec, $Rows, [string]$SingleLabel)
        $Field = $Spec.field
        $Aggregate = { param($Numbers) if (@($Numbers).Count -eq 0) { return 0 }
            $Nums = if ($Spec.scale) { @($Numbers | ForEach-Object { $_ / $Spec.scale }) } else { @($Numbers) }
            $Measured = $Nums | Measure-Object -Sum -Average -Minimum -Maximum
            switch ($Spec.aggregate) { 'avg' { [math]::Round($Measured.Average, 2) } 'min' { $Measured.Minimum } 'max' { $Measured.Maximum } default { $Measured.Sum } } }
        $Pairs = if ($Spec.valueField) {
            if ($Field) {
                @($Rows | Group-Object { @(& $ValueOf $_ $Field | ForEach-Object { "$_" }) | Select-Object -First 1 } | ForEach-Object {
                        $Label = "$($_.Name)"
                        if (-not $Label) { return }
                        $Numbers = @($_.Group | ForEach-Object { @(& $ValueOf $_ $Spec.valueField | ForEach-Object { $_ -as [double] } | Where-Object { $null -ne $_ }) | Select-Object -First 1 } | Where-Object { $null -ne $_ })
                        if ($Numbers.Count -eq 0) { return }
                        @{ label = $Label; value = [double](& $Aggregate $Numbers) }
                    })
            } else {
                $Numbers = @($Rows | ForEach-Object { @(& $ValueOf $_ $Spec.valueField | ForEach-Object { $_ -as [double] } | Where-Object { $null -ne $_ }) | Select-Object -First 1 } | Where-Object { $null -ne $_ })
                @(@{ label = $(if ($SingleLabel) { $SingleLabel } else { $Spec.type }); value = [double](& $Aggregate $Numbers) })
            }
        } elseif ($Field) {
            $Groups = @(foreach ($Row in $Rows) { @(& $ValueOf $Row $Field | ForEach-Object { "$_" }) }) | Group-Object { $_.ToLowerInvariant() }
            @($Groups | ForEach-Object { @{ label = "$($_.Group[0])"; value = [double]$_.Count } })
        } else {
            @(@{ label = $(if ($SingleLabel) { $SingleLabel } else { $Spec.type }); value = [double]$Rows.Count })
        }
        @($Pairs | Sort-Object -Property @{ Expression = { $_.value }; Descending = $true }, @{ Expression = { $_.label } } | Select-Object -First $MaxSlices)
    }

    foreach ($Block in @($Blocks)) {
        if ($null -eq $Block) { continue }
        $Type = "$($Block.type)"

        # A chart drawn from the data. Counting rows: one slice per distinct value of the field, the long
        # tail as Other, or a single counted slice when no field was picked. Plotting a field's value:
        # one point per row labelled by the field - chronological when the labels are dates, which is
        # how a Secure Score trend reads - or, with an aggregate, one point per label.
        if ($Type -eq 'chart' -and $Block.chartSource) {
            $Spec = & $SourceOf $Block.chartSource
            $Rows = if ($Spec) { & $RowsFor $Spec }
            if ($Spec -and $null -ne $Rows) {
                $Field = $Spec.field
                $Points = if ($Spec.valueField) {
                    $Series = @(foreach ($Row in $Rows) {
                            $Number = @(& $ValueOf $Row $Spec.valueField | ForEach-Object { $_ -as [double] } | Where-Object { $null -ne $_ }) | Select-Object -First 1
                            if ($null -eq $Number) { continue }
                            if ($Spec.scale) { $Number = [double]$Number / $Spec.scale }
                            $Raw = if ($Field) { @(& $ValueOf $Row $Field | ForEach-Object { "$_" }) | Select-Object -First 1 } else { $null }
                            $Date = [datetime]::MinValue
                            $IsDate = $null -ne $Raw -and [datetime]::TryParse("$Raw", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Date)
                            @{ raw = $Raw; value = [double]$Number; date = $(if ($IsDate) { $Date }) }
                        })
                    if ($Spec.aggregate) {
                        $Combined = @($Series | Group-Object { "$($_.raw)".ToLowerInvariant() } | ForEach-Object {
                                $Measured = @($_.Group | ForEach-Object { $_.value }) | Measure-Object -Sum -Average -Maximum -Minimum
                                $Figure = switch ($Spec.aggregate) { 'avg' { [math]::Round($Measured.Average, 2) } 'max' { $Measured.Maximum } 'min' { $Measured.Minimum } default { $Measured.Sum } }
                                @{ label = "$($_.Group[0].raw)"; value = [double]$Figure }
                            })
                        @($Combined | Sort-Object -Property @{ Expression = { $_.value }; Descending = $true }, @{ Expression = { $_.label } } | Select-Object -First $MaxSlices)
                    } elseif ($Series.Count -gt 0 -and @($Series | Where-Object { $null -ne $_.date }).Count -eq $Series.Count) {
                        $Ordered = @($Series | Sort-Object -Property { $_.date } | Select-Object -Last $MaxPoints)
                        $Format = if (@($Ordered | ForEach-Object { $_.date.Year } | Select-Object -Unique).Count -gt 1) { 'MMM d yyyy' } else { 'MMM d' }
                        @($Ordered | ForEach-Object { @{ label = $_.date.ToString($Format, [cultureinfo]::InvariantCulture); value = $_.value } })
                    } else {
                        @($Series | Select-Object -Last $MaxPoints | ForEach-Object { @{ label = $(if ($null -ne $_.raw) { "$($_.raw)" } else { '' }); value = $_.value } })
                    }
                } elseif ($Field) {
                    $Groups = @(foreach ($Row in $Rows) { @(& $ValueOf $Row $Field | ForEach-Object { "$_" }) }) | Group-Object { $_.ToLowerInvariant() } | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Name'; Descending = $false }
                    $Blank = @($Rows | Where-Object { @(& $ValueOf $_ $Field).Count -eq 0 }).Count
                    $Top = @($Groups | Select-Object -First $MaxSlices | ForEach-Object { @{ label = $_.Group[0]; value = $_.Count } })
                    $Rest = @($Groups | Select-Object -Skip $MaxSlices | Measure-Object -Property Count -Sum).Sum
                    @($Top; if ($Rest -gt 0) { @{ label = 'Other'; value = [int]$Rest } }; if ($Blank -gt 0) { @{ label = '(blank)'; value = $Blank } })
                } else {
                    @(@{ label = $(if ($Block.title) { "$($Block.title)" } else { $Spec.type }); value = $Rows.Count })
                }
                & $SetProperty $Block 'chartData' @($Points)
            }
        }

        # A table filled from the data: the rows (the ones the condition keeps), each column reading
        # the field it names. A dataSource with a preset instead calls a derived builder for data that a
        # flat single-collection read cannot express (e.g. the Secure Score controls, nested per snapshot);
        # either way the same column mapping fills the table.
        if ($Type -eq 'richtable' -and $Block.dataSource) {
            $TablePreset = "$($Block.dataSource.preset)"
            $Rows = if ($TablePreset) {
                $Source = & $RowsOf "$($Block.dataSource.type)"
                if ($null -ne $Source) { try { @(Get-CippReportTableData -Preset $TablePreset -Rows @($Source)) } catch { $null } }
            } else {
                $Spec = & $SourceOf $Block.dataSource
                if ($Spec) { & $RowsFor $Spec }
            }
            if ($null -ne $Rows) {
                $Columns = @($Block.columns)
                $TableRows = @(foreach ($Row in (@($Rows) | Select-Object -First $MaxRows)) {
                        $Cells = [ordered]@{}
                        foreach ($Column in $Columns) {
                            $Key = "$($Column.key)"
                            $From = if ($Column.field) { "$($Column.field)" } else { "$($Column.header)" }
                            $Cells[$Key] = (@(& $ValueOf $Row $From | ForEach-Object { "$_" }) -join ', ')
                        }
                        $Cells
                    })
                & $SetProperty $Block 'rows' @($TableRows)
                if (-not $Block.limit) { & $SetProperty $Block 'limit' $MaxRows }
            }
        }

        # Score cards drawn from the data: one card per distinct value of the field, the figure a count
        # of rows (or an aggregate of a numeric field). Manual stats stay hand-typed and can use tokens.
        if ($Type -eq 'scorecard' -and $Block.statsSource) {
            $Spec = & $SourceOf $Block.statsSource
            $Rows = if ($Spec) { & $RowsFor $Spec }
            if ($Spec -and $null -ne $Rows) {
                $Cards = @(& $CardsFrom $Spec @($Rows) "$($Block.title)" | ForEach-Object { @{ value = (& $FormatNumber $_.value); label = $_.label } })
                if ($Cards.Count -gt 0) { & $SetProperty $Block 'stats' @($Cards) }
            }
        }

        # Progress bars drawn from the data: one bar per distinct value of the field, filled by its share
        # of the total (counting rows) or of the largest bar (aggregating a numeric field).
        if ($Type -eq 'progress' -and $Block.itemsSource) {
            $Spec = & $SourceOf $Block.itemsSource
            $Rows = if ($Spec) { & $RowsFor $Spec }
            if ($Spec -and $null -ne $Rows) {
                $Bars = @(& $CardsFrom $Spec @($Rows) "$($Block.title)")
                if ($Bars.Count -gt 0) {
                    $Max = if ($Spec.valueField) { [double](@($Bars | ForEach-Object { $_.value }) | Measure-Object -Maximum).Maximum } else { [double]@($Rows).Count }
                    if ($Max -le 0) { $Max = [double](@($Bars | ForEach-Object { $_.value }) | Measure-Object -Maximum).Maximum }
                    $Items = @($Bars | ForEach-Object { @{ label = $_.label; value = $_.value; max = $Max } })
                    & $SetProperty $Block 'items' @($Items)
                }
            }
        }

        # A sankey (flow diagram) drawn from the data. Three shapes:
        #   preset   - a faithful server-side port of a dashboard sankey (MFA coverage, auth methods,
        #              licence allocation, device compliance); Get-CippReportSankeyData does the exact
        #              per-sankey computation the dashboard card does, so the report matches the dashboard.
        #   measures - one category field on the left, plus numeric measure fields, each a right-hand
        #              node; every row adds category -> measureLabel weighted by that field.
        #   flow     - an ordered list of categorical fields; each adjacent pair (a, b) becomes a link
        #              a -> b weighted by the number of rows (or the sum of valueField). Node ids are
        #              namespaced by stage so a value shared between two columns does not fold/cycle.
        if ($Type -eq 'sankey' -and $Block.sankeySource) {
            $Sankey = $Block.sankeySource
            $CollectionType = "$($Sankey.type)"
            $Rows = if ($CollectionType) { & $RowsOf $CollectionType }
            if ($null -ne $Rows -and $Sankey.preset) {
                # Faithful dashboard sankey - the ported card logic owns the whole {nodes, links}.
                $Built = try { Get-CippReportSankeyData -Preset "$($Sankey.preset)" -Rows @($Rows) } catch { $null }
                if ($Built -and @($Built.links).Count -gt 0) {
                    & $SetProperty $Block 'nodes' @($Built.nodes)
                    & $SetProperty $Block 'links' @($Built.links)
                }
            } elseif ($null -ne $Rows) {
                $SankeyFilter = $Sankey.filter
                if ($SankeyFilter -and $SankeyFilter.field -and $SankeyFilter.op) {
                    $Rows = @($Rows | Where-Object { & $RowMatches $_ "$($SankeyFilter.field)" "$($SankeyFilter.op)" "$($SankeyFilter.value)" })
                }
                $NodeOrder = [System.Collections.Generic.List[string]]::new()
                $NodeLabel = @{}
                $NodeColour = @{}
                $LinkValue = [ordered]@{}
                $Palette = { param([int]$Index) 'hsl({0}, 70%, 50%)' -f ((205 + $Index * 37) % 360) }
                $AddNode = {
                    param([string]$Id, [string]$Label, [string]$Colour)
                    if (-not $NodeLabel.ContainsKey($Id)) {
                        $NodeOrder.Add($Id)
                        $NodeLabel[$Id] = $Label
                        $NodeColour[$Id] = if ($Colour) { $Colour } else { & $Palette ($NodeOrder.Count - 1) }
                    }
                }
                $AddLink = {
                    param([string]$Source, [string]$Target, [double]$Value)
                    $Key = "$Source`n$Target"
                    $LinkValue[$Key] = ([double]($LinkValue[$Key]) + $Value)
                }

                if ("$($Sankey.mode)" -eq 'measures') {
                    $CategoryField = "$($Sankey.field)"
                    $Measures = @($Sankey.measures)
                    $Limit = if (($Sankey.limit -as [int]) -gt 0) { [int]$Sankey.limit } else { 8 }
                    # Rank categories by their total across all measures, keep the top N.
                    $CategoryTotals = @{}
                    foreach ($Row in $Rows) {
                        $Category = @(& $ValueOf $Row $CategoryField | ForEach-Object { "$_" }) | Select-Object -First 1
                        if (-not $Category) { continue }
                        foreach ($Measure in $Measures) {
                            $Number = @(& $ValueOf $Row "$($Measure.field)" | ForEach-Object { $_ -as [double] } | Where-Object { $null -ne $_ }) | Select-Object -First 1
                            if ($null -ne $Number) { $CategoryTotals[$Category] = ([double]($CategoryTotals[$Category]) + [double]$Number) }
                        }
                    }
                    $KeepCategories = @($CategoryTotals.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First $Limit -ExpandProperty Key)
                    foreach ($Row in $Rows) {
                        $Category = @(& $ValueOf $Row $CategoryField | ForEach-Object { "$_" }) | Select-Object -First 1
                        if (-not $Category -or $Category -notin $KeepCategories) { continue }
                        & $AddNode $Category $Category $null
                        foreach ($Measure in $Measures) {
                            $Label = if ($Measure.label) { "$($Measure.label)" } else { "$($Measure.field)" }
                            $Number = @(& $ValueOf $Row "$($Measure.field)" | ForEach-Object { $_ -as [double] } | Where-Object { $null -ne $_ }) | Select-Object -First 1
                            if ($null -eq $Number -or $Number -le 0) { continue }
                            & $AddNode "measure:$Label" $Label "$($Measure.colour)"
                            & $AddLink $Category "measure:$Label" ([double]$Number)
                        }
                    }
                } else {
                    # flow: an ordered list of categorical fields; adjacent pairs become links. Node ids are
                    # namespaced by stage index so the same value in two columns stays two nodes.
                    $Fields = @($Sankey.fields | Where-Object { $_ } | ForEach-Object { "$_" })
                    $ValueField = if ($Sankey.valueField) { "$($Sankey.valueField)" }
                    if ($Fields.Count -ge 2) {
                        foreach ($Row in $Rows) {
                            $Weight = if ($ValueField) {
                                @(& $ValueOf $Row $ValueField | ForEach-Object { $_ -as [double] } | Where-Object { $null -ne $_ }) | Select-Object -First 1
                            } else { 1 }
                            if ($null -eq $Weight -or $Weight -le 0) { continue }
                            $Stages = @(for ($si = 0; $si -lt $Fields.Count; $si++) {
                                    $Value = @(& $ValueOf $Row $Fields[$si] | ForEach-Object { "$_" }) | Select-Object -First 1
                                    if (-not $Value) { $Value = '(blank)' }
                                    [pscustomobject]@{ Id = ('{0}:{1}' -f $si, $Value); Label = "$Value" }
                                })
                            foreach ($Stage in $Stages) { & $AddNode $Stage.Id $Stage.Label $null }
                            for ($i = 0; $i -lt $Stages.Count - 1; $i++) { & $AddLink $Stages[$i].Id $Stages[$i + 1].Id ([double]$Weight) }
                        }
                    }
                }

                if ($NodeOrder.Count -gt 0 -and $LinkValue.Count -gt 0) {
                    $Nodes = @(foreach ($Id in $NodeOrder) { @{ id = $Id; label = $NodeLabel[$Id]; nodeColor = $NodeColour[$Id] } })
                    $Links = @(foreach ($Key in $LinkValue.Keys) {
                            $Parts = $Key -split "`n", 2
                            @{ source = $Parts[0]; target = $Parts[1]; value = $LinkValue[$Key] }
                        })
                    & $SetProperty $Block 'nodes' @($Nodes)
                    & $SetProperty $Block 'links' @($Links)
                }
            }
        }

        # Every other string on the block, its rows and its items.
        if ($Block -is [System.Collections.IDictionary]) {
            foreach ($Name in @($Block.Keys)) { if ($Name -notin 'chartSource', 'dataSource', 'sankeySource', 'statsSource', 'itemsSource') { $Block[$Name] = & $Walk $Block[$Name] } }
        } else {
            foreach ($Property in @($Block.PSObject.Properties)) { if ($Property.Name -notin 'chartSource', 'dataSource', 'sankeySource', 'statsSource', 'itemsSource') { $Block.($Property.Name) = & $Walk $Property.Value } }
        }
    }

    # Unrolled, not wrapped: callers collect with @(), and a wrapped array would reach them as one
    # element holding every block - which the renderer then draws as nothing at all.
    return $Blocks
}
