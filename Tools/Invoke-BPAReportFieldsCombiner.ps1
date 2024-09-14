<#
.SYNOPSIS
    This script combines the 'Fields' properties from multiple BPATemplate.json files into a new JSON file.

.DESCRIPTION
    The script reads all BPATemplate.json files from a specified directory, excluding the output file itself.
    It combines the 'Fields' properties from all these files and creates a new output file using a predefined JSON template.
    The output file is recreated every time the script runs, ensuring that the 'Fields' property is updated with combined data.

.INPUTS
    None. You cannot pipe objects to this script.

.OUTPUTS
    None. The script directly creates or overwrites a JSON file with the combined 'Fields' data.

.NOTES
    The script will automatically find all BPATemplate.json files in the specified directory if no input files are provided.
    The output JSON file is always created or overwritten based on the provided outputFileName.

.EXAMPLE
    .\Update-BPATemplates.ps1 -outputFileName "TABLE-ALL" -outputReportName "All" -Directory "./Config"

    This example finds all BPATemplate.json files in the ./Config directory, combines their 'Fields' properties, 
    and creates/overwrites a TABLE-ALL.BPATemplate.json file with the combined 'Fields'.

#>

param (
    [string]$outputFileName = "TABLE-ALL", 
    [string]$outputReportName = "All",
    [string]$Directory = "./Config",
    [string[]]$inputFiles = @() # Leave empty to automatically find all BPATemplate.json files in the directory
)

$outputFile = "$Directory/$outputFileName.BPATemplate.json"

# JSON template that will be used to recreate the file
$template = @{
    "name"   = $outputReportName
    "style"  = "Table"
    "Fields" = @()
}

# If no input files are provided, list all .json files from the input directory
if ($inputFiles.Count -eq 0) {
    if (Test-Path $inputDirectory) {
        # Get all JSON files from the input directory that end with BPATemplate.json
        $inputFiles = Get-ChildItem -Path $inputDirectory -Filter *BPATemplate.json -Exclude "$outputFileName.BPATemplate.json" -Recurse | Select-Object -ExpandProperty FullName
        Write-Host "Automatically found the following files:" -ForegroundColor Green
        $inputFiles | ForEach-Object { Write-Host $_ }
    }
    else {
        Write-Host "Input directory does not exist. Please provide a valid directory path." -ForegroundColor Red
        exit 1
    }
}

# Initialize an empty array to hold the combined Fields
$combinedFields = @()

# Iterate through each input file
foreach ($filePath in $inputFiles) {
    if (Test-Path $filePath) {
        $inputFile = Get-Content -Raw -Path $filePath | ConvertFrom-Json
        
        # Ensure the 'Fields' property exists in the input file
        if ($inputFile.PSObject.Properties.Match('Fields')) {
            # Append fields from the current file to the combinedFields array
            $combinedFields += $inputFile.Fields
        }
        else {
            Write-Host "Fields property not found in file: $filePath" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Input file does not exist: $filePath" -ForegroundColor Red
    }
}

# Update the Fields in the template with the combinedFields array
$template.Fields = $combinedFields

# Write the recreated JSON structure to the output file, overwriting if it exists
$template | ConvertTo-Json -Depth 10 | Set-Content -Path $outputFile

Write-Host "New JSON file created and saved to: $outputFile" -ForegroundColor Green
