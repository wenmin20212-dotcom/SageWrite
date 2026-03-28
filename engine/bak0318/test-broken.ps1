param(
    [string]$Name
)

Write-Host "Starting test script..."

if ($Name -eq "") {
    Write-Host "Name is empty"
} else {
    $result = 10 / 1
    Write-Host "Result is $result"
}

Write-Host "Script completed."


