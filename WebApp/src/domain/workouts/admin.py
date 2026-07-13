from django.contrib import admin

from .models import (
    MuscleGroup, WorkoutFolder, Exercise, ExerciseCategory, Equipment,
    WorkoutPlan, WorkoutDay, WorkoutExercise,
)


@admin.register(ExerciseCategory)
class ExerciseCategoryAdmin(admin.ModelAdmin):
    list_display = ('name_it', 'name_en', 'wger_id')
    search_fields = ('name_it', 'name_en')
    ordering = ('name_it',)


@admin.register(Equipment)
class EquipmentAdmin(admin.ModelAdmin):
    list_display = ('name_it', 'name_en', 'wger_id')
    search_fields = ('name_it', 'name_en')
    ordering = ('name_it',)


@admin.register(MuscleGroup)
class MuscleGroupAdmin(admin.ModelAdmin):
    list_display = ('name', 'slug', 'region', 'color_token', 'order')
    list_filter = ('region',)
    search_fields = ('name', 'slug')
    ordering = ('region', 'order')
    prepopulated_fields = {'slug': ('name',)}


@admin.register(WorkoutFolder)
class WorkoutFolderAdmin(admin.ModelAdmin):
    list_display = ('title', 'coach', 'label_text', 'label_color', 'order')
    list_filter = ('coach',)
    search_fields = ('title', 'label_text')
    ordering = ('coach', 'order')


@admin.register(Exercise)
class ExerciseAdmin(admin.ModelAdmin):
    list_display = (
        'name', 'is_custom', 'created_by',
        'category', 'updated_at',
    )
    list_filter = ('is_custom', 'category')
    search_fields = ('name',)
    filter_horizontal = ('equipment', 'primary_muscles', 'secondary_muscles')
    readonly_fields = ('created_at', 'updated_at')
    fieldsets = (
        ('Identificazione', {
            'fields': (
                'name', 'slug', 'description', 'aliases',
                'cover_image', 'is_custom', 'created_by',
            ),
        }),
        ('Tassonomia', {
            'fields': ('category', 'equipment', 'primary_muscles', 'secondary_muscles'),
        }),
        ('Fonte wger.de', {
            'classes': ('collapse',),
            'fields': (
                'wger_id', 'wger_uuid', 'wger_image_url',
                'license_title', 'license_author',
            ),
        }),
        ('Meta', {
            'fields': ('coach_notes', 'created_at', 'updated_at'),
        }),
    )


@admin.register(WorkoutPlan)
class WorkoutPlanAdmin(admin.ModelAdmin):
    list_display = ('title', 'coach', 'plan_kind', 'folder',
                    'status', 'duration_weeks', 'updated_at')
    list_filter = ('plan_kind', 'status', 'is_template')
    search_fields = ('title', 'coach__user__email')
    raw_id_fields = ('coach', 'folder')


@admin.register(WorkoutDay)
class WorkoutDayAdmin(admin.ModelAdmin):
    list_display = ('workout_plan', 'day_order', 'day_name')
    raw_id_fields = ('workout_plan',)


@admin.register(WorkoutExercise)
class WorkoutExerciseAdmin(admin.ModelAdmin):
    list_display = ('exercise', 'workout_day', 'order_index',
                    'set_count', 'rep_range', 'execution_type')
    list_filter = ('execution_type',)
    raw_id_fields = ('workout_day', 'exercise', 'alternative_exercise')
