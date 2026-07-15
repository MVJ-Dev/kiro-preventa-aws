"""
Ejemplo de Diagrama de Arquitectura AWS — Referencia para el equipo
Usa: pip install diagrams + graphviz instalado en el sistema

Para ejecutar:
    python3 diagrama-ejemplo.py

Si graphviz no está instalado con apt:
    PATH="/tmp/gvenv/bin:$PATH" python3 diagrama-ejemplo.py
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import ECS, Fargate, AutoScaling
from diagrams.aws.network import ALB, NATGateway, Route53, CloudFront
from diagrams.aws.database import Aurora, ElastiCache
from diagrams.aws.storage import SimpleStorageServiceS3 as S3
from diagrams.aws.security import WAF, KMS
from diagrams.aws.management import Cloudwatch
from diagrams.aws.general import Users

graph_attr = {
    "fontsize": "14",
    "bgcolor": "white",
    "pad": "0.8",
    "nodesep": "0.8",
    "ranksep": "1.2",
    "labelloc": "t",
    "fontname": "Helvetica-Bold",
}

with Diagram(
    "Ejemplo - App Web HA Multi-AZ",
    show=False,
    filename="ejemplo-arquitectura",
    outformat="png",
    direction="TB",
    graph_attr=graph_attr,
):
    users = Users("Usuarios")

    with Cluster("AWS Account"):
        dns = Route53("Route 53")
        cdn = CloudFront("CloudFront")
        waf = WAF("WAF")

        with Cluster("us-east-1"):
            with Cluster("VPC - Produccion"):

                with Cluster("Public Subnets"):
                    alb = ALB("ALB")
                    nat = NATGateway("NAT Gateway")

                with Cluster("Private Subnets - App"):
                    with Cluster("AZ-a"):
                        app_a = Fargate("App Task")
                    with Cluster("AZ-b"):
                        app_b = Fargate("App Task")

                with Cluster("Private Subnets - Data"):
                    with Cluster("AZ-a"):
                        db_writer = Aurora("Writer")
                    with Cluster("AZ-b"):
                        db_reader = Aurora("Reader")

                cache = ElastiCache("Redis Cache")

            s3 = S3("Assets / Backups")
            cw = Cloudwatch("CloudWatch")

    # Flujos
    users >> Edge(color="#1565C0", style="bold") >> dns
    dns >> cdn >> waf >> alb

    alb >> Edge(label="HTTPS", color="#2E7D32") >> app_a
    alb >> Edge(color="#2E7D32") >> app_b

    app_a >> Edge(color="#6A1B9A") >> db_writer
    app_b >> Edge(color="#6A1B9A") >> db_writer
    db_writer >> Edge(label="replication", color="#6A1B9A", style="dashed") >> db_reader

    app_a >> Edge(color="#E65100", style="dashed") >> cache
    app_b >> Edge(color="#E65100", style="dashed") >> cache

    app_a >> Edge(color="#455A64", style="dotted") >> nat
    app_a >> Edge(color="#C62828", style="dotted") >> cw
