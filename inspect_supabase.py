"""Query Supabase to inspect massive payment and contract data."""
from supabase import create_client, Client

url = "https://bucnrydgojyzntgesxqb.supabase.co"
key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ1Y25yeWRnb2p5em50Z2VzeHFiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyNzI1MTQsImV4cCI6MjA4ODg0ODUxNH0.iW08JEDYM7s2SOVIKqHYK05Td-t6GdBNvEdnec5gJQA"

supabase: Client = create_client(url, key)

# Let's fetch the 5 most recent payments from pagos_contrato_alumno
try:
    res = supabase.from_("pagos_contrato_alumno").select("*, contratos_alumnos(*)").limit(5).execute()
    data = res.data
    print(f"Fetched {len(data)} payments:")
    for idx, p in enumerate(data):
        c = p.get("contratos_alumnos", {})
        print(f"\n[{idx+1}] Pago ID: {p.get('id')}")
        print(f"    Concepto: {p.get('concepto')}")
        print(f"    Monto: {p.get('monto')}")
        print(f"    Fecha Pago: {p.get('fecha_pago')}")
        if c:
            print(f"    Contrato ID: {c.get('id')}")
            print(f"    Alumno: {c.get('nombre_alumno')}")
            print(f"    Cuotas Pagadas (Contrato): {c.get('cuotas_pagadas')}")
            print(f"    Total Cuotas (Contrato): {c.get('total_cuotas')}")
            print(f"    Saldo Deudor: {c.get('saldo_deudor')}")
        else:
            print("    No contract associated.")
except Exception as e:
    print("Error querying Supabase:", e)
