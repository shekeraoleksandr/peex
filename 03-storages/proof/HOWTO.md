# How to fill this folder

`proof/` is empty in the kit. Run the scripts on the machine where your `aws`
CLI is logged in (region us-east-1) and the evidence is written here:

```bash
./provision.sh      # -> 01_provision.txt
./iam-setup.sh      # -> 02_iam.txt
./test-access.sh    # -> 03_access_tests.txt
```

These map 1:1 to the PeEx "Outcome Artifacts":

| Artifact required                                   | Proof file / content |
|-----------------------------------------------------|----------------------|
| Storage service created, showing configuration      | 01_provision.txt |
| Public access blocked                               | 01_provision.txt (get-public-access-block) |
| Encryption at rest enabled                          | 01_provision.txt (get-bucket-encryption) |
| Versioning enabled                                  | 01_provision.txt + 03 (list-object-versions) |
| IAM roles/policies configuration showing permissions| 02_iam.txt (+ policies/*.json) |
| Upload success with read-write role                 | 03_access_tests.txt (RW section) |
| Download success with read-only role                | 03_access_tests.txt (RO section) |
| Upload FAILURE with read-only role                  | 03_access_tests.txt (RO upload rc != 0) |
| Access control testing results                      | 03_access_tests.txt (policy simulation) |

Optionally add S3 console screenshots here for visual confirmation.
