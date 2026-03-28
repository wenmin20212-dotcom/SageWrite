param(
    [string]$Name
)

Write-Host "Starting test script..."

# Intentional syntax error below
if ($Name -eq "") 
    Write-Host "Name is empty"

# Intentional runtime error
$result = 10 / 0

Write-Host "Result is $result"
Write-Host "Script completed."