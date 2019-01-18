# Generated by Django 2.1.4 on 2018-12-28 22:57

from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('aquifers', '0008_alter_sequence'),
        ('wells', '0046_auto_20181213_2216'),
    ]

    operations = [
        migrations.AddField(
            model_name='activitysubmission',
            name='aquifer',
            field=models.ForeignKey(blank=True, db_column='aquifer_id', null=True, on_delete=django.db.models.deletion.PROTECT, to='aquifers.Aquifer', verbose_name='Aquifer ID Number'),
        ),
    ]
