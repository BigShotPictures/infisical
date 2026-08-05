terraform {
  # Partial configuration — bucket/prefix are supplied at `tofu init` time via
  # a *.gcs.tfbackend file so this config isn't tied to one project/bucket.
  # See README.md for the one-time bucket bootstrap and init command.
  backend "gcs" {}
}
