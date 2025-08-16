import setuptools

setuptools.setup(
    name="beam-file-ingestion-pipeline",
    version="0.1.0",
    description="Files ingestion pipeline with Apache Beam",
    packages=setuptools.find_packages(include=["beam", "beam.*"]),
    install_requires=[
        "apache-beam[gcp]>=2.58.0",  # match your local beam version
        "python-dotenv",
    ],
)
