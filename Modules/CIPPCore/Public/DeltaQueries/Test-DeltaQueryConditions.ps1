function Test-DeltaQueryConditions {
    <#
    .SYNOPSIS
        Tests if the conditions for a Delta Query trigger are met.
    .DESCRIPTION
        This function evaluates whether the specified conditions for a Delta Query trigger are satisfied based on the provided data.
    .PARAMETER Query
        The result of the delta query to evaluate.
    .PARAMETER Trigger
        The trigger configuration containing conditions to test against.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Query,
        [Parameter(Mandatory = $true)]
        $Trigger,
        [Parameter(Mandatory = $true)]
        $TenantFilter,
        [Parameter(Mandatory = $true)]
        $LastTrigger
    )

    $ConditionsMet = $false
    $MatchedData = @()

    $Data = $Query.value
    $EventType = $Trigger.EventType.value ?? $Trigger.EventType

    # Filter data based on delta query change type according to Microsoft Graph specification
    switch ($EventType) {
        'deleted' {
            Write-Information "data to process for deleted: $($Data | ConvertTo-Json -Depth 5)"
            # Removed instances are represented by their id and an @removed object
            $Data = $Data | Where-Object {
                $_.PSObject.Properties.Name -contains '@removed' -and $_.'@removed'.reason -eq 'changed'
            }

            # For directory objects, fetch full details of deleted items
            Write-Information 'Fetching full details for deleted directory objects.'

            $Requests = foreach ($item in $Data) {
                [PSCustomObject]@{
                    'id'     = $item.id
                    'url'    = "directory/deletedItems/$($item.id)"
                    'method' = 'GET'
                }
            }
            try {
                $DeletedItems = New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter
                if ($DeletedItems.status -eq 200) {
                    Write-Information 'Retrieved full details for deleted items.'
                    Write-Information "Deleted items response: $($DeletedItems | ConvertTo-Json -Depth 5)"
                    $EnrichedData = [System.Collections.Generic.List[object]]::new()
                    foreach ($Row in $Data) {
                        $fullItem = ($DeletedItems | Where-Object { $_.id -eq $Row.id -and $_.status -eq 200 }).body
                        if ($fullItem) {
                            $EnrichedData.Add($fullItem)
                        } else {
                            $EnrichedData.Add($Row)
                        }
                    }
                    $Data = $EnrichedData
                }
            } catch {
                Write-Warning "Failed to retrieve full details for deleted items: $($_.Exception.Message)"
            }

            Write-Information "Found $($Data.Count) deleted items."
        }
        'created' {
            # Newly created instances use standard representation without @removed
            # These will have their full standard representation, not minimal response
            $Data = $Data | Where-Object { $_.createdDateTime -ge $LastTrigger }
            Write-Information "Found $($Data.Count) created items."
        }
        'updated' {
            # Updated instances have at least updated properties but no @removed object
            $Data = $Data | Where-Object {
                $_.PSObject.Properties.Name -notcontains '@removed' -and
                (!$_.createdDateTime -or $_.createdDateTime -lt $LastTrigger)
            }
            Write-Information "Found $($Data.Count) updated items."
        }
    }

    # Check if we have any data after event type filtering
    if (($Data | Measure-Object).Count -eq 0) {
        Write-Information "No data matches the event type filter '$EventType'. Conditions not met."
        return @{
            ConditionsMet     = $false
            MatchedData       = @()
            TotalItems        = ($Query.value | Measure-Object).Count
            FilteredItems     = 0
            MatchedItems      = 0
            EventTypeFilter   = $EventType
            ChangeTypeSummary = @()
        }
    }

    if ($Trigger.UseConditions -eq $true -and $Trigger.Conditions) {
        try {
            # Parse conditions from JSON (similar to audit log processing)
            $conditions = $Trigger.Conditions | ConvertFrom-Json | Where-Object { $_.Input.value -ne '' -and $_.Input.value -ne $null }

            if ($conditions) {
                # Initialize collections for condition strings
                $conditionStrings = [System.Collections.Generic.List[string]]::new()
                $CIPPClause = [System.Collections.Generic.List[string]]::new()

                foreach ($condition in $conditions) {
                    # Handle array vs single values
                    $value = if ($condition.Input.value -is [array]) {
                        $arrayAsString = $condition.Input.value | ForEach-Object {
                            "'$_'"
                        }
                        "@($($arrayAsString -join ', '))"
                    } else {
                        "'$($condition.Input.value)'"
                    }

                    # Build PowerShell condition string
                    $conditionStrings.Add("`$(`$_.$($condition.Property.label)) -$($condition.Operator.value) $value")
                    $CIPPClause.Add("$($condition.Property.label) is $($condition.Operator.label) $value")
                }

                # Join all conditions with AND
                $finalCondition = $conditionStrings -join ' -AND '

                Write-Information "Testing delta query conditions: $finalCondition"
                Write-Information "Human readable: $($CIPPClause -join ' and ')"

                # Apply conditions to filter the data using a script block instead of Invoke-Expression
                $scriptBlock = [scriptblock]::Create("param(`$_) $finalCondition")
                $MatchedData = $Data | Where-Object $scriptBlock
            } else {
                Write-Information 'No valid conditions found in trigger configuration.'
                $MatchedData = $Data
            }
        } catch {
            Write-Warning "Error processing delta query conditions: $($_.Exception.Message)"
            Write-Information $_.InvocationInfo.PositionMessage
            $MatchedData = @()
        }
    } else {
        # No conditions specified, consider all data as matching
        $MatchedData = $Data
    }

    # Determine if conditions are met based on final matched data count
    $ConditionsMet = ($MatchedData | Measure-Object).Count -gt 0

    # Return results with matched data and change type summary
    $changeTypeSummary = $MatchedData | Group-Object CIPPChangeType | ForEach-Object {
        @{
            ChangeType = $_.Name
            Count      = $_.Count
        }
    }

    return @{
        ConditionsMet     = $ConditionsMet
        MatchedData       = $MatchedData
        TotalItems        = ($Query.value | Measure-Object).Count
        FilteredItems     = ($Data | Measure-Object).Count
        MatchedItems      = ($MatchedData | Measure-Object).Count
        EventTypeFilter   = $EventType
        ChangeTypeSummary = $changeTypeSummary
    }

}
