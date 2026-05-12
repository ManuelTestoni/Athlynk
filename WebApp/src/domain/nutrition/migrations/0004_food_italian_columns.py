from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('nutrition', '0003_supplement_supplementsheet_supplementassignment_and_more'),
    ]

    operations = [
        # 1) Pin existing fields to their target db_columns BEFORE renaming Python attrs.
        migrations.AlterField(
            model_name='food',
            name='name',
            field=models.CharField(max_length=200, db_column='Nome_Alimento'),
        ),
        migrations.AlterField(
            model_name='food',
            name='category',
            field=models.CharField(max_length=100, null=True, blank=True, db_column='Categoria_Alimento'),
        ),
        migrations.AlterField(
            model_name='food',
            name='kcal_per_100g',
            field=models.FloatField(default=0, db_column='Energia(Kcal)'),
        ),
        migrations.AlterField(
            model_name='food',
            name='protein_per_100g',
            field=models.FloatField(default=0, db_column='Proteine(g)'),
        ),
        migrations.AlterField(
            model_name='food',
            name='fat_per_100g',
            field=models.FloatField(default=0, db_column='Lipidi(g)'),
        ),
        migrations.AlterField(
            model_name='food',
            name='carb_per_100g',
            field=models.FloatField(default=0, db_column='Carboidrati(g)'),
        ),
        migrations.AlterField(
            model_name='food',
            name='sugar_per_100g',
            field=models.FloatField(default=0, db_column='Carboidrati_Solubili(g)'),
        ),
        migrations.AlterField(
            model_name='food',
            name='fiber_per_100g',
            field=models.FloatField(default=0, db_column='Fibra(g)'),
        ),

        # 2) Rename Python attrs (db_column unchanged).
        migrations.RenameField(model_name='food', old_name='name', new_name='nome_alimento'),
        migrations.RenameField(model_name='food', old_name='category', new_name='categoria_alimento'),
        migrations.RenameField(model_name='food', old_name='kcal_per_100g', new_name='energia_kcal'),
        migrations.RenameField(model_name='food', old_name='protein_per_100g', new_name='proteine_g'),
        migrations.RenameField(model_name='food', old_name='fat_per_100g', new_name='lipidi_g'),
        migrations.RenameField(model_name='food', old_name='carb_per_100g', new_name='carboidrati_g'),
        migrations.RenameField(model_name='food', old_name='sugar_per_100g', new_name='carboidrati_solubili_g'),
        migrations.RenameField(model_name='food', old_name='fiber_per_100g', new_name='fibra_g'),

        # 3) Add new nutrient fields.
        migrations.AddField(model_name='food', name='colesterolo_mg',
            field=models.FloatField(default=0, db_column='Colesterolo(mg)')),
        migrations.AddField(model_name='food', name='fe_mg',
            field=models.FloatField(default=0, db_column='Fe(mg)')),
        migrations.AddField(model_name='food', name='ca_mg',
            field=models.FloatField(default=0, db_column='Ca(mg)')),
        migrations.AddField(model_name='food', name='na_mg',
            field=models.FloatField(default=0, db_column='Na(mg)')),
        migrations.AddField(model_name='food', name='k_mg',
            field=models.FloatField(default=0, db_column='K(mg)')),
        migrations.AddField(model_name='food', name='p_mg',
            field=models.FloatField(default=0, db_column='P(mg)')),
        migrations.AddField(model_name='food', name='zn_mg',
            field=models.FloatField(default=0, db_column='Zn(mg)')),
        migrations.AddField(model_name='food', name='mg_mg',
            field=models.FloatField(default=0, db_column='Mg(mg)')),
        migrations.AddField(model_name='food', name='cu_mg',
            field=models.FloatField(default=0, db_column='Cu(mg)')),
        migrations.AddField(model_name='food', name='se_ug',
            field=models.FloatField(default=0, db_column='Se(ug)')),
        migrations.AddField(model_name='food', name='i_ug',
            field=models.FloatField(default=0, db_column='I(ug)')),
        migrations.AddField(model_name='food', name='mn_mg',
            field=models.FloatField(default=0, db_column='Mn(mg)')),
        migrations.AddField(model_name='food', name='vit_b1_mg',
            field=models.FloatField(default=0, db_column='Vit_B1(mg)')),
        migrations.AddField(model_name='food', name='vit_b2_mg',
            field=models.FloatField(default=0, db_column='Vit_B2(mg)')),
        migrations.AddField(model_name='food', name='vit_c_mg',
            field=models.FloatField(default=0, db_column='Vit_C(mg)')),
        migrations.AddField(model_name='food', name='niacina_mg',
            field=models.FloatField(default=0, db_column='Niacina(mg)')),
        migrations.AddField(model_name='food', name='vit_b6_mg',
            field=models.FloatField(default=0, db_column='Vit_B6(mg)')),
        migrations.AddField(model_name='food', name='folati_ug',
            field=models.FloatField(default=0, db_column='Folati(ug)')),
        migrations.AddField(model_name='food', name='vit_b12_ug',
            field=models.FloatField(default=0, db_column='Vit_B12(ug)')),
        migrations.AddField(model_name='food', name='lipidi_saturi_g',
            field=models.FloatField(default=0, db_column='Lipidi_Saturi(g)')),
        migrations.AddField(model_name='food', name='isoleucina_mg',
            field=models.FloatField(default=0, db_column='Isoleucina(mg)')),
        migrations.AddField(model_name='food', name='leucina_mg',
            field=models.FloatField(default=0, db_column='Leucina(mg)')),
        migrations.AddField(model_name='food', name='valina_mg',
            field=models.FloatField(default=0, db_column='Valina(mg)')),
        migrations.AddField(model_name='food', name='lattosio_g',
            field=models.FloatField(default=0, db_column='Lattosio(g)')),

        # 4) Reorder by Italian name attr.
        migrations.AlterModelOptions(
            name='food',
            options={'ordering': ['nome_alimento']},
        ),
    ]
