
# conftest.py
import snowflake.connector
import os, sys, logging, pytest, traceback
from dotenv import load_dotenv

print("=== DEBUG PATHS ===")
print("__file__:", __file__)
# Fix path - point to current tests directory (not src/)
PROJECT_ROOT = os.path.abspath(os.path.dirname(__file__))
print("PROJECT_ROOT:", PROJECT_ROOT)
print("Exists sf_client.py?:", os.path.isfile(os.path.join(PROJECT_ROOT, "sf_client.py")))
print("sys.path head:", sys.path[:5])

if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

print("sys.path head (after):", sys.path[:5])
print("Try import sf_client…")
try:
    import sf_client
    print("Imported sf_client OK.")
    print("Members:", [m for m in dir(sf_client) if m.lower().startswith("snowflakeclient") or m=="SnowflakeClient"])
except Exception:
    print("FAILED import sf_client. Full traceback below:")
    traceback.print_exc()
    raise

from sf_client import SnowflakeClient

load_dotenv()

# Optionally configure root logging once for tests
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger(__name__)

def pytest_addoption(parser):
    parser.addoption('--sf-account',   action='store', default=os.getenv('SNOWFLAKE_ACCOUNT'))
    # parser.addoption('--sf-host',      action='store', default=os.getenv('SNOWFLAKE_HOST'))
    parser.addoption('--sf-user',      action='store', default=os.getenv('SNOWFLAKE_USER'))
    # parser.addoption('--sf-password',  action='store', default=os.getenv('SNOWFLAKE_PASSWORD'))
    parser.addoption('--sf-role',      action='store', default=os.getenv('SNOWFLAKE_ROLE'))
    parser.addoption('--sf-warehouse', action='store', default=os.getenv('SNOWFLAKE_WAREHOUSE'))
    parser.addoption('--sf-database',  action='store', default=os.getenv('SNOWFLAKE_DATABASE'))
    parser.addoption('--sf-schema',    action='store', default=os.getenv('SNOWFLAKE_SCHEMA'))
    parser.addoption('--disable-ocsp', action='store_true', default=False)
    # JWT / key-pair auth options
    parser.addoption('--sf-authenticator', action='store',
                     default=os.getenv('SNOWFLAKE_AUTHENTICATOR', 'SNOWFLAKE_JWT'))
    parser.addoption('--sf-private-key-path', action='store',
                     default=os.getenv('SNOWFLAKE_PRIVATE_KEY_PATH'))


@pytest.fixture(scope="session")
def sf_conn(pytestconfig):
    """Snowflake connection with JWT authentication support"""
    auth = pytestconfig.getoption('--sf-authenticator')
    
    conn_params = {
        'account': pytestconfig.getoption('--sf-account'),
        'user': pytestconfig.getoption('--sf-user'),
        'role': pytestconfig.getoption('--sf-role'),
        'warehouse': pytestconfig.getoption('--sf-warehouse'),
        'database': pytestconfig.getoption('--sf-database'),
        'schema': pytestconfig.getoption('--sf-schema')
    }
    
    # Use JWT authentication if configured
    if auth == 'SNOWFLAKE_JWT':
        private_key_path = pytestconfig.getoption('--sf-private-key-path')
        if private_key_path:
            # Expand ~ to home directory
            private_key_path = os.path.expanduser(private_key_path)
            
            with open(private_key_path, 'rb') as key_file:
                private_key_data = key_file.read()
            
            from cryptography.hazmat.backends import default_backend
            from cryptography.hazmat.primitives import serialization
            
            p_key = serialization.load_pem_private_key(
                private_key_data,
                password=None,
                backend=default_backend()
            )
            
            pkb = p_key.private_bytes(
                encoding=serialization.Encoding.DER,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption()
            )
            
            conn_params['private_key'] = pkb
            conn_params['authenticator'] = 'SNOWFLAKE_JWT'
            log.info('Using JWT authentication with private key')
        else:
            raise ValueError("JWT auth selected but no private key path provided")
    else:
        # Fall back to password authentication if needed
        password = pytestconfig.getoption('--sf-password', default=None)
        if password:
            conn_params['password'] = password
    
    conn = snowflake.connector.connect(**conn_params)
    cur = conn.cursor()
    log.info('✅ Snowflake connection opened')
    yield cur
    log.info('Closing Snowflake connection.')
    cur.close()
    conn.close()

@pytest.fixture(scope='session')
def sf(pytestconfig):
    client = SnowflakeClient(
        account=pytestconfig.getoption('--sf-account'),
        # host=pytestconfig.getoption('--sf-host'),
        user=pytestconfig.getoption('--sf-user'),
        password=pytestconfig.getoption('--sf-password'),
        role=pytestconfig.getoption('--sf-role'),
        warehouse=pytestconfig.getoption('--sf-warehouse'),
        database=pytestconfig.getoption('--sf-database'),
        schema=pytestconfig.getoption('--sf-schema'),
        disable_ocsp_checks=pytestconfig.getoption('--disable-ocsp'),
    )
    log.info('Opening Snowflake connection...')
    client.connect()
    yield client
    log.info('Closing Snowflake connection.')
    client.close()
