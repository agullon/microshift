// Code generated by client-gen. DO NOT EDIT.

package v1

import (
	"context"

	v1 "github.com/openshift/api/build/v1"
	buildv1 "github.com/openshift/client-go/build/applyconfigurations/build/v1"
	scheme "github.com/openshift/client-go/build/clientset/versioned/scheme"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	types "k8s.io/apimachinery/pkg/types"
	watch "k8s.io/apimachinery/pkg/watch"
	gentype "k8s.io/client-go/gentype"
)

// BuildConfigsGetter has a method to return a BuildConfigInterface.
// A group's client should implement this interface.
type BuildConfigsGetter interface {
	BuildConfigs(namespace string) BuildConfigInterface
}

// BuildConfigInterface has methods to work with BuildConfig resources.
type BuildConfigInterface interface {
	Create(ctx context.Context, buildConfig *v1.BuildConfig, opts metav1.CreateOptions) (*v1.BuildConfig, error)
	Update(ctx context.Context, buildConfig *v1.BuildConfig, opts metav1.UpdateOptions) (*v1.BuildConfig, error)
	// Add a +genclient:noStatus comment above the type to avoid generating UpdateStatus().
	UpdateStatus(ctx context.Context, buildConfig *v1.BuildConfig, opts metav1.UpdateOptions) (*v1.BuildConfig, error)
	Delete(ctx context.Context, name string, opts metav1.DeleteOptions) error
	DeleteCollection(ctx context.Context, opts metav1.DeleteOptions, listOpts metav1.ListOptions) error
	Get(ctx context.Context, name string, opts metav1.GetOptions) (*v1.BuildConfig, error)
	List(ctx context.Context, opts metav1.ListOptions) (*v1.BuildConfigList, error)
	Watch(ctx context.Context, opts metav1.ListOptions) (watch.Interface, error)
	Patch(ctx context.Context, name string, pt types.PatchType, data []byte, opts metav1.PatchOptions, subresources ...string) (result *v1.BuildConfig, err error)
	Apply(ctx context.Context, buildConfig *buildv1.BuildConfigApplyConfiguration, opts metav1.ApplyOptions) (result *v1.BuildConfig, err error)
	// Add a +genclient:noStatus comment above the type to avoid generating ApplyStatus().
	ApplyStatus(ctx context.Context, buildConfig *buildv1.BuildConfigApplyConfiguration, opts metav1.ApplyOptions) (result *v1.BuildConfig, err error)
	Instantiate(ctx context.Context, buildConfigName string, buildRequest *v1.BuildRequest, opts metav1.CreateOptions) (*v1.Build, error)

	BuildConfigExpansion
}

// buildConfigs implements BuildConfigInterface
type buildConfigs struct {
	*gentype.ClientWithListAndApply[*v1.BuildConfig, *v1.BuildConfigList, *buildv1.BuildConfigApplyConfiguration]
}

// newBuildConfigs returns a BuildConfigs
func newBuildConfigs(c *BuildV1Client, namespace string) *buildConfigs {
	return &buildConfigs{
		gentype.NewClientWithListAndApply[*v1.BuildConfig, *v1.BuildConfigList, *buildv1.BuildConfigApplyConfiguration](
			"buildconfigs",
			c.RESTClient(),
			scheme.ParameterCodec,
			namespace,
			func() *v1.BuildConfig { return &v1.BuildConfig{} },
			func() *v1.BuildConfigList { return &v1.BuildConfigList{} }),
	}
}

// Instantiate takes the representation of a buildRequest and creates it.  Returns the server's representation of the build, and an error, if there is any.
func (c *buildConfigs) Instantiate(ctx context.Context, buildConfigName string, buildRequest *v1.BuildRequest, opts metav1.CreateOptions) (result *v1.Build, err error) {
	result = &v1.Build{}
	err = c.GetClient().Post().
		Namespace(c.GetNamespace()).
		Resource("buildconfigs").
		Name(buildConfigName).
		SubResource("instantiate").
		VersionedParams(&opts, scheme.ParameterCodec).
		Body(buildRequest).
		Do(ctx).
		Into(result)
	return
}
