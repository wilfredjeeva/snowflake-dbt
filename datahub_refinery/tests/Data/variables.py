# Environment Variable - dynamically set based on SNOWFLAKE_DATABASE
import os

# Get environment from SNOWFLAKE_DATABASE (e.g., "DEV_BRONZE_ADF" -> "DEV")
database = os.getenv('SNOWFLAKE_DATABASE', 'DEV_BRONZE_ADF')
env_prefix = database.split('_')[0]  # Extract "DEV", "TEST", "PREPROD", or "PROD"

# Dynamic database names
landing_db = f"{env_prefix}_LANDING_ADF"
bronze_db = f"{env_prefix}_BRONZE_ADF"

# Schema and Table names (same across all environments)
airBnB_schema = "AIRBNB"
airBnB_table = "AIRBNBDRIVERS"